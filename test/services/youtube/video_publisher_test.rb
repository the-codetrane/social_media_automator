# frozen_string_literal: true

require "test_helper"

module YouTube
  class VideoPublisherTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user        = users(:one)
      @publisher   = YouTube::VideoPublisher.new(@user)
      @short_asset = media_assets(:sample_video)       # duration_seconds: 30.5
      @long_asset  = media_assets(:sample_long_video)  # duration_seconds: 120.0
      @image_asset = media_assets(:sample_image)
    end

    # Replaces the publisher's internal ApiClient with a lightweight double
    # and stubs URI.open so no real HTTP requests are made.
    def with_stub_client(video_id: "yt_video_001", &block)
      fake_result = Struct.new(:id).new(video_id)
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) { |_path, _video, **| fake_result }
      @publisher.instance_variable_set(:@client, mock_client)

      fake_io = StringIO.new("fake video bytes")
      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(fake_io) }) do
        block.call(mock_client)
      end
    end

    def new_youtube_post(asset:, caption: "Test caption", platform_payload: nil)
      PlannedPost.create!(
        user:             @user,
        media_asset:      asset,
        platform:         :youtube,
        status:           :draft,
        scheduled_at:     nil,
        caption:          caption,
        hashtags:         "#test",
        platform_payload: platform_payload
      )
    end

    # -------------------------------------------------------------------------
    # #publish — happy path (Short)
    # -------------------------------------------------------------------------

    test "publish uploads a Short and marks the post published" do
      post = new_youtube_post(asset: @short_asset, caption: "Quick clip")

      with_stub_client(video_id: "yt_short_001") do
        result = @publisher.publish(post)
        assert_equal "yt_short_001", result
      end

      post.reload
      assert post.published?
      assert_equal "yt_short_001", post.external_post_id
      assert_not_nil post.published_at
      assert_equal "yt_short_001", post.platform_payload["youtube_video_id"]
      assert_equal true, post.platform_payload["short"]
    end

    test "publish uploads a full video and marks the post published" do
      post = new_youtube_post(asset: @long_asset, caption: "Feature film")

      with_stub_client(video_id: "yt_video_001") do
        result = @publisher.publish(post)
        assert_equal "yt_video_001", result
      end

      post.reload
      assert post.published?
      assert_equal false, post.platform_payload["short"]
    end

    # -------------------------------------------------------------------------
    # Short detection
    # -------------------------------------------------------------------------

    test "short? returns true when duration_seconds < 60" do
      assert @short_asset.duration_seconds < 60
      post = new_youtube_post(asset: @short_asset)

      captured_snippet = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_snippet = video.snippet
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      assert_match(/#Shorts/, captured_snippet.title)
      assert_match(/#Shorts/, captured_snippet.description)
    end

    test "short? returns false when duration_seconds >= 60" do
      assert @long_asset.duration_seconds >= 60
      post = new_youtube_post(asset: @long_asset)

      captured_snippet = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_snippet = video.snippet
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      refute_match(/#Shorts/, captured_snippet.title)
      refute_match(/#Shorts/, captured_snippet.description)
    end

    test "short? returns false when duration_seconds is nil" do
      @short_asset.update_column(:duration_seconds, nil)
      post = new_youtube_post(asset: @short_asset)

      captured_snippet = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_snippet = video.snippet
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      refute_match(/#Shorts/, captured_snippet.title)
    ensure
      @short_asset.update_column(:duration_seconds, 30.5)
    end

    # -------------------------------------------------------------------------
    # Title / description building
    # -------------------------------------------------------------------------

    test "title uses first line of caption and truncates to 100 chars" do
      long_caption = "A" * 110 + "\nSecond line"
      post = new_youtube_post(asset: @long_asset, caption: long_caption)

      captured_snippet = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_snippet = video.snippet
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      assert captured_snippet.title.length <= 100
      refute_match(/Second line/, captured_snippet.title)
    end

    test "title defaults to 'YouTube Video' when caption is blank" do
      post = new_youtube_post(asset: @long_asset, caption: "")

      captured_snippet = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_snippet = video.snippet
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      assert_match(/YouTube Video/, captured_snippet.title)
    end

    # -------------------------------------------------------------------------
    # platform_payload optional params
    # -------------------------------------------------------------------------

    test "forwards privacy_status and category_id from platform_payload" do
      post = new_youtube_post(
        asset:            @long_asset,
        platform_payload: { "privacy_status" => "unlisted", "category_id" => "17" }
      )

      captured_status   = nil
      captured_category = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_status   = video.status.privacy_status
        captured_category = video.snippet.category_id
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      assert_equal "unlisted", captured_status
      assert_equal "17", captured_category
    end

    test "defaults privacy_status to public when not in platform_payload" do
      post = new_youtube_post(asset: @long_asset)

      captured_status = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) do |_path, video, **|
        captured_status = video.status.privacy_status
        Struct.new(:id).new("yt_001")
      end
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        @publisher.publish(post)
      end

      assert_equal "public", captured_status
    end

    # -------------------------------------------------------------------------
    # Validation errors
    # -------------------------------------------------------------------------

    test "raises ArgumentError when media_asset is not a video" do
      post = new_youtube_post(asset: @image_asset)
      # Override media_type guard by using the image asset directly
      post.update_column(:media_asset_id, @image_asset.id)

      err = assert_raises(ArgumentError) { @publisher.publish(post) }
      assert_match(/video MediaAsset/i, err.message)
    end

    test "raises ApiError when the asset has no public URL" do
      no_url_asset = media_assets(:sample_image_no_url)
      no_url_asset.update_column(:media_type, MediaAsset.media_types[:video])

      post = new_youtube_post(asset: no_url_asset)

      err = assert_raises(YouTube::ApiError) { @publisher.publish(post) }
      assert_match(/no public URL/i, err.message)
    ensure
      no_url_asset.update_column(:media_type, MediaAsset.media_types[:image])
    end

    # -------------------------------------------------------------------------
    # Error handling
    # -------------------------------------------------------------------------

    test "marks post as failed and re-raises on YouTube::Error" do
      post = new_youtube_post(asset: @short_asset)

      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) { |*_| raise YouTube::ApiError, "server error" }
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        assert_raises(YouTube::ApiError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end

    test "raises UploadError when API returns no video ID" do
      post = new_youtube_post(asset: @short_asset)

      mock_client = Object.new
      mock_client.define_singleton_method(:upload_video) { |*_| Struct.new(:id).new(nil) }
      @publisher.instance_variable_set(:@client, mock_client)

      URI.stub(:open, ->(_url, _mode, &blk) { blk.call(StringIO.new("x")) }) do
        assert_raises(YouTube::UploadError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end
  end
end
