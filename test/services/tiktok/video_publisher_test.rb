# frozen_string_literal: true

require "test_helper"

module TikTok
  class VideoPublisherTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    DEFAULT_CREATOR_INFO = {
      "creator_username"            => "cainandco",
      "creator_nickname"            => "Cain & Co.",
      "privacy_level_options"       => %w[PUBLIC_TO_EVERYONE MUTUAL_FOLLOW_FRIENDS SELF_ONLY],
      "comment_disabled"            => false,
      "duet_disabled"               => false,
      "stitch_disabled"             => false,
      "max_video_post_duration_sec" => 600
    }.freeze

    def setup
      @user        = users(:one)
      @publisher   = TikTok::VideoPublisher.new(@user)
      @video_asset = media_assets(:sample_video)       # 30.5s, video/mp4
      @long_asset  = media_assets(:sample_long_video)  # 120.0s
      @image_asset = media_assets(:sample_image)
    end

    # A stand-in for TikTok::ApiClient that records what the publisher sent.
    #
    # @param statuses [Array<String>] status values returned by successive
    #   status/fetch calls; the last one repeats once exhausted.
    class FakeClient
      attr_reader :init_body, :chunks, :status_calls

      def initialize(publish_id:, upload_url:, statuses:, post_ids:, init_error: nil)
        @publish_id   = publish_id
        @upload_url   = upload_url
        @statuses     = statuses.dup
        @post_ids     = post_ids
        @init_error   = init_error
        @chunks       = []
        @status_calls = 0
      end

      def post(path, body = {})
        case path
        when TikTok::VideoPublisher::INIT_ENDPOINT
          raise @init_error if @init_error
          @init_body = body
          { "data" => { "publish_id" => @publish_id, "upload_url" => @upload_url } }
        when TikTok::VideoPublisher::STATUS_ENDPOINT
          @status_calls += 1
          status = @statuses.size > 1 ? @statuses.shift : @statuses.first
          {
            "data" => {
              "status"                      => status,
              "publicaly_available_post_id" => @post_ids,
              "fail_reason"                 => status == "FAILED" ? "video_format_check_failed" : nil
            }.compact
          }
        else
          raise "unexpected path #{path}"
        end
      end

      def upload_chunk(upload_url, bytes, content_type:, first_byte:, last_byte:, total_bytes:)
        @chunks << {
          upload_url: upload_url, size: bytes.bytesize, content_type: content_type,
          first_byte: first_byte, last_byte: last_byte, total_bytes: total_bytes
        }
        last_byte == total_bytes - 1 ? 201 : 206
      end
    end

    # Wire up the publisher with a fake client, fake creator info and a fake
    # download, then run the block.  Yields the FakeClient.
    def with_stubs(creator: DEFAULT_CREATOR_INFO, publish_id: "v_pub_file~v2.001",
                   upload_url: "https://upload.tiktokapis.com/upload/001",
                   statuses: [ "PUBLISH_COMPLETE" ], post_ids: [ "7123456789" ],
                   bytes: "fake video bytes", init_error: nil)
      client = FakeClient.new(publish_id:, upload_url:, statuses:, post_ids:, init_error:)
      @publisher.instance_variable_set(:@client, client)

      info = Object.new
      info.define_singleton_method(:query) { creator }

      TikTok::CreatorInfoService.stub(:new, info) do
        URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new(bytes)) }) do
          @publisher.stub(:sleep, nil) do
            yield client
          end
        end
      end
    end

    def new_tiktok_post(asset: @video_asset, caption: "Live from the studio", hashtags: "#blues", platform_payload: nil)
      PlannedPost.create!(
        user:             @user,
        media_asset:      asset,
        platform:         :tiktok,
        status:           :draft,
        scheduled_at:     nil,
        caption:          caption,
        hashtags:         hashtags,
        platform_payload: platform_payload
      )
    end

    # -------------------------------------------------------------------------
    # #publish — happy path
    # -------------------------------------------------------------------------

    test "publish initialises, uploads and marks the post published" do
      post = new_tiktok_post

      result = with_stubs { @publisher.publish(post) }

      assert_equal "v_pub_file~v2.001", result

      post.reload
      assert post.published?
      assert_equal "v_pub_file~v2.001", post.external_post_id
      assert_not_nil post.published_at
      assert_equal "v_pub_file~v2.001", post.platform_payload["tiktok_publish_id"]
      assert_equal "7123456789",        post.platform_payload["tiktok_post_id"]
      assert_equal "PUBLIC_TO_EVERYONE", post.platform_payload["privacy_level"]
      assert_equal "PUBLISH_COMPLETE",   post.platform_payload["publish_status"]
    end

    test "publish sends a FILE_UPLOAD source_info matching the downloaded file" do
      post  = new_tiktok_post
      bytes = "x" * 1024

      client = nil
      with_stubs(bytes: bytes) { |c| client = c; @publisher.publish(post) }

      source = client.init_body[:source_info]
      assert_equal "FILE_UPLOAD", source[:source]
      assert_equal 1024, source[:video_size]
      assert_equal 1024, source[:chunk_size]
      assert_equal 1,    source[:total_chunk_count]
    end

    test "publish builds the title from the caption and hashtags" do
      post = new_tiktok_post(caption: "Doors at 8", hashtags: "#blues #livemusic")

      client = nil
      with_stubs { |c| client = c; @publisher.publish(post) }

      assert_equal "Doors at 8\n\n#blues #livemusic", client.init_body[:post_info][:title]
    end

    test "publish truncates a title longer than TikTok's limit" do
      post = new_tiktok_post(caption: "a" * 3000, hashtags: nil)

      client = nil
      with_stubs { |c| client = c; @publisher.publish(post) }

      assert_equal TikTok::VideoPublisher::MAX_TITLE_LENGTH, client.init_body[:post_info][:title].length
    end

    test "publish preserves existing platform_payload keys" do
      post = new_tiktok_post(platform_payload: { "source" => "chat", "privacy_level" => "SELF_ONLY" })

      with_stubs { @publisher.publish(post) }

      assert_equal "chat",      post.reload.platform_payload["source"]
      assert_equal "SELF_ONLY", post.platform_payload["privacy_level"]
    end

    # -------------------------------------------------------------------------
    # Chunking
    # -------------------------------------------------------------------------

    test "chunk_plan uploads a sub-5MB file as a single whole-file chunk" do
      plan = @publisher.send(:chunk_plan, 1_000_000)
      assert_equal({ chunk_size: 1_000_000, total_chunk_count: 1 }, plan)
    end

    test "chunk_plan uploads a file between the min and max chunk size as one chunk" do
      size = 40 * 1024 * 1024
      plan = @publisher.send(:chunk_plan, size)
      assert_equal({ chunk_size: size, total_chunk_count: 1 }, plan)
    end

    test "chunk_plan splits a large file into 64MB chunks with the remainder on the last" do
      size = 200 * 1024 * 1024
      plan = @publisher.send(:chunk_plan, size)

      assert_equal TikTok::VideoPublisher::MAX_CHUNK_SIZE, plan[:chunk_size]
      assert_equal 3, plan[:total_chunk_count]

      # The final chunk absorbs the remainder and must stay under TikTok's 128MB cap.
      final_chunk = size - (plan[:total_chunk_count] - 1) * plan[:chunk_size]
      assert_operator final_chunk, :<=, 128 * 1024 * 1024
    end

    test "chunk_plan rejects a file needing more than 1000 chunks" do
      too_big = (TikTok::VideoPublisher::MAX_CHUNK_SIZE * TikTok::VideoPublisher::MAX_CHUNK_COUNT) + TikTok::VideoPublisher::MAX_CHUNK_SIZE
      assert_raises(TikTok::UploadError) { @publisher.send(:chunk_plan, too_big) }
    end

    test "chunk_plan rejects an empty file" do
      assert_raises(TikTok::UploadError) { @publisher.send(:chunk_plan, 0) }
    end

    test "publish uploads sequential chunks covering the whole file" do
      post = new_tiktok_post
      size = 150 * 1024 * 1024

      client = nil
      with_stubs(bytes: "y" * size) { |c| client = c; @publisher.publish(post) }

      assert_equal 2, client.chunks.size
      assert_equal 0, client.chunks.first[:first_byte]
      assert_equal size - 1, client.chunks.last[:last_byte]
      assert_equal size, client.chunks.sum { |c| c[:size] }
      assert_equal client.chunks.first[:last_byte] + 1, client.chunks.last[:first_byte]
      assert client.chunks.all? { |c| c[:total_bytes] == size }
      assert client.chunks.all? { |c| c[:content_type] == "video/mp4" }
    end

    # -------------------------------------------------------------------------
    # Creator info constraints
    # -------------------------------------------------------------------------

    test "publish defaults to PUBLIC_TO_EVERYONE" do
      post = new_tiktok_post

      client = nil
      with_stubs { |c| client = c; @publisher.publish(post) }

      assert_equal "PUBLIC_TO_EVERYONE", client.init_body[:post_info][:privacy_level]
    end

    test "publish honours a privacy_level from platform_payload" do
      post = new_tiktok_post(platform_payload: { "privacy_level" => "SELF_ONLY" })

      client = nil
      with_stubs { |c| client = c; @publisher.publish(post) }

      assert_equal "SELF_ONLY", client.init_body[:post_info][:privacy_level]
    end

    test "publish raises PermanentError for a privacy level the creator cannot use" do
      post    = new_tiktok_post(platform_payload: { "privacy_level" => "FOLLOWER_OF_CREATOR" })
      creator = DEFAULT_CREATOR_INFO.merge("privacy_level_options" => %w[SELF_ONLY])

      with_stubs(creator: creator) do
        error = assert_raises(TikTok::PermanentError) { @publisher.publish(post) }
        assert_match(/not available for this creator/, error.message)
      end

      assert post.reload.failed?
    end

    test "publish forces disable_comment when the creator has comments switched off" do
      post    = new_tiktok_post
      creator = DEFAULT_CREATOR_INFO.merge("comment_disabled" => true)

      client = nil
      with_stubs(creator: creator) { |c| client = c; @publisher.publish(post) }

      assert_equal true, client.init_body[:post_info][:disable_comment]
    end

    test "publish forwards the interaction toggles from platform_payload" do
      post = new_tiktok_post(platform_payload: {
        "disable_duet" => true, "disable_stitch" => true, "is_aigc" => true,
        "video_cover_timestamp_ms" => 1500
      })

      client = nil
      with_stubs { |c| client = c; @publisher.publish(post) }

      info = client.init_body[:post_info]
      assert_equal true,  info[:disable_duet]
      assert_equal true,  info[:disable_stitch]
      assert_equal false, info[:disable_comment]
      assert_equal true,  info[:is_aigc]
      assert_equal 1500,  info[:video_cover_timestamp_ms]
    end

    test "publish raises PermanentError when the video exceeds the creator's duration cap" do
      post    = new_tiktok_post(asset: @long_asset)
      creator = DEFAULT_CREATOR_INFO.merge("max_video_post_duration_sec" => 60)

      with_stubs(creator: creator) do
        error = assert_raises(TikTok::PermanentError) { @publisher.publish(post) }
        assert_match(/can only post videos up to 60s/, error.message)
      end

      assert post.reload.failed?
    end

    # -------------------------------------------------------------------------
    # Status polling
    # -------------------------------------------------------------------------

    test "publish polls until the upload reaches PUBLISH_COMPLETE" do
      post = new_tiktok_post

      client = nil
      with_stubs(statuses: %w[PROCESSING_UPLOAD PROCESSING_UPLOAD PUBLISH_COMPLETE]) do |c|
        client = c
        @publisher.publish(post)
      end

      assert_equal 3, client.status_calls
      assert post.reload.published?
    end

    test "publish treats SEND_TO_USER_INBOX as a terminal success" do
      post = new_tiktok_post

      with_stubs(statuses: [ "SEND_TO_USER_INBOX" ], post_ids: nil) { @publisher.publish(post) }

      assert post.reload.published?
      assert_equal "SEND_TO_USER_INBOX", post.platform_payload["publish_status"]
      assert_nil post.platform_payload["tiktok_post_id"]
    end

    test "publish raises and fails the post when TikTok reports FAILED" do
      post = new_tiktok_post

      with_stubs(statuses: [ "FAILED" ]) do
        error = assert_raises(TikTok::ApiError) { @publisher.publish(post) }
        assert_match(/video_format_check_failed/, error.message)
      end

      assert post.reload.failed?
    end

    test "wait_until_published! raises PublishTimeoutError when processing never finishes" do
      client = FakeClient.new(publish_id: "v_pub_001", upload_url: "https://upload.example/1",
                              statuses: [ "PROCESSING_UPLOAD" ], post_ids: nil)
      @publisher.instance_variable_set(:@client, client)

      travel_to Time.current
      # Each poll's sleep advances the clock, so the deadline arrives without waiting.
      @publisher.stub(:sleep, ->(seconds) { travel_to Time.current + seconds }) do
        assert_raises(TikTok::PublishTimeoutError) do
          @publisher.send(:wait_until_published!, "v_pub_001", timeout: 10)
        end
      end

      assert_operator client.status_calls, :>, 1, "expected more than one poll before timing out"
    end

    # -------------------------------------------------------------------------
    # Validation and error handling
    # -------------------------------------------------------------------------

    # PlannedPost blocks this at save time, so reaching the publisher means the
    # post predates that validation or had its asset swapped. It must fail the
    # post rather than crash the job, hence PermanentError over ArgumentError.
    test "publish rejects a non-video asset as a permanent failure" do
      post = new_tiktok_post(asset: @video_asset)
      post.update_column(:media_asset_id, @image_asset.id)
      post.reload

      with_stubs do
        error = assert_raises(TikTok::PermanentError) { @publisher.publish(post) }
        assert_match(/requires a video MediaAsset/, error.message)
      end

      assert post.reload.failed?
    end

    test "publish raises PermanentError when the asset has no public URL" do
      asset = media_assets(:sample_image_no_url)
      asset.update!(media_type: :video, mime_type: "video/mp4")
      post  = new_tiktok_post(asset: asset)  # valid: media_type is now :video

      with_stubs do
        assert_raises(TikTok::PermanentError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end

    test "publish marks the post failed and re-raises when init is rejected" do
      post = new_tiktok_post

      with_stubs(init_error: TikTok::RateLimitError.new("quota exhausted", code: "spam_risk_too_many_posts")) do
        assert_raises(TikTok::RateLimitError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end

    test "publish raises ApiError when TikTok returns no publish_id" do
      post = new_tiktok_post

      with_stubs(publish_id: nil) do
        assert_raises(TikTok::ApiError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end

    test "publish raises ApiError when TikTok returns no upload_url" do
      post = new_tiktok_post

      with_stubs(upload_url: nil) do
        assert_raises(TikTok::ApiError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end
  end
end
