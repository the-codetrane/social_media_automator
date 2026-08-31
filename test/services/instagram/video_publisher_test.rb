# frozen_string_literal: true

require "test_helper"

module Instagram
  class VideoPublisherTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user      = users(:one)
      @publisher = Instagram::VideoPublisher.new(@user)
      @ig_id     = @user.instagram_user_id

      @video_asset = media_assets(:sample_video)
      @image_asset = media_assets(:sample_image)
    end

    # Replace the publisher's internal ApiClient with a lightweight double.
    def stub_client(container_id: "cont_video_001", media_id: "ig_media_video_001",
                    status_code: "FINISHED", quota_usage: 1, quota_total: 25)
      mock_client = Object.new

      mock_client.define_singleton_method(:publishing_limit) do |_|
        { "data" => [ { "quota_usage" => quota_usage, "config" => { "quota_total" => quota_total } } ] }
      end

      mock_client.define_singleton_method(:get) do |_path, _params = {}|
        { "status_code" => status_code }
      end

      mock_client.define_singleton_method(:post) do |path, _body = {}|
        path.end_with?("/media_publish") ? { "id" => media_id } : { "id" => container_id }
      end

      @publisher.instance_variable_set(:@client, mock_client)
      mock_client
    end

    # -------------------------------------------------------------------------
    # #publish — happy path
    # -------------------------------------------------------------------------

    test "publish creates a REELS container, polls until FINISHED, and publishes" do
      container_id = "cont_reel_001"
      media_id     = "ig_reel_001"

      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil,
        caption:      "Amazing reel!",
        hashtags:     "#reels #viral"
      )

      captured_media_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        if path.end_with?("/media_publish")
          { "id" => media_id }
        else
          captured_media_params = body
          { "id" => container_id }
        end
      end

      @publisher.instance_variable_set(:@client, mock_client)

      result = @publisher.publish(post)

      assert_equal media_id, result
      post.reload
      assert post.published?
      assert_equal media_id, post.external_post_id
      assert_not_nil post.published_at
      assert_equal media_id, post.platform_payload["ig_media_id"]
      assert_equal "REELS", post.platform_payload["media_type"]
      assert_equal container_id, post.platform_payload["container_id"]

      # Verify the Meta API params
      assert_not_nil captured_media_params
      assert_equal "REELS", captured_media_params[:media_type]
      assert_equal "https://cdn.example.com/reel.mp4", captured_media_params[:video_url]
      assert_equal "Amazing reel!\n\n#reels #viral", captured_media_params[:caption]
    end

    test "share_to_feed defaults to true when not set in platform_payload" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      captured_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        path.end_with?("/media_publish") ? { "id" => "m1" } : (captured_params = body; { "id" => "c1" })
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_equal "true", captured_params[:share_to_feed]
    end

    test "forwards optional platform_payload params to the Meta API" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @video_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        caption:          "My reel",
        platform_payload: {
          "share_to_feed"  => false,
          "cover_url"      => "https://cdn.example.com/cover.jpg",
          "thumb_offset"   => 2000,
          "audio_name"     => "My Track",
          "location_id"    => "987654321",
          "collaborators"  => [ "user_a", "user_b" ]
        }
      )

      captured_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        path.end_with?("/media_publish") ? { "id" => "m1" } : (captured_params = body; { "id" => "c1" })
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_not_nil captured_params
      assert_equal "false",                            captured_params[:share_to_feed]
      assert_equal "https://cdn.example.com/cover.jpg", captured_params[:cover_url]
      assert_equal "2000",                             captured_params[:thumb_offset]
      assert_equal "My Track",                         captured_params[:audio_name]
      assert_equal "987654321",                        captured_params[:location_id]
      assert_equal [ "user_a", "user_b" ].to_json,    captured_params[:collaborators]
    end

    # -------------------------------------------------------------------------
    # #publish — validation errors
    # -------------------------------------------------------------------------

    test "raises ArgumentError when media_asset is not a video" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @image_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(ArgumentError) { @publisher.publish(post) }
        assert_match(/video MediaAsset/i, err.message)
        assert_match(@image_asset.id.to_s, err.message)
      end
    end

    test "raises ApiError when the video asset has no public URL" do
      no_url_asset = media_assets(:sample_image_no_url)
      # Temporarily override media_type so it passes the video check
      no_url_asset.update_column(:media_type, MediaAsset.media_types[:video])

      post = PlannedPost.create!(
        user:         @user,
        media_asset:  no_url_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/no public URL/i, err.message)
      end
    ensure
      no_url_asset.update_column(:media_type, MediaAsset.media_types[:image])
    end

    test "marks post as failed and re-raises when an Instagram::Error occurs" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| raise Instagram::ApiError, "server error" }
      mock_client.define_singleton_method(:get)  { |*_| { "status_code" => "FINISHED" } }

      @publisher.instance_variable_set(:@client, mock_client)

      assert_raises(Instagram::ApiError) { @publisher.publish(post) }
      assert post.reload.failed?
    end

    test "marks post as failed when container enters ERROR status" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| { "id" => "cont_001" } }
      mock_client.define_singleton_method(:get)  { |*_| { "status_code" => "ERROR", "status" => "encoding failed" } }

      @publisher.instance_variable_set(:@client, mock_client)

      err = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
      assert_match(/ERROR/i, err.message)
      assert post.reload.failed?
    end

    # -------------------------------------------------------------------------
    # Quota check
    # -------------------------------------------------------------------------

    test "raises RateLimitError when publishing quota is exhausted" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 25, "config" => { "quota_total" => 25 } } ] } }

      @publisher.instance_variable_set(:@client, mock_client)

      err = assert_raises(Instagram::RateLimitError) { @publisher.publish(post) }
      assert_match(/quota exhausted/i, err.message)
      assert post.reload.failed?
    end

    # -------------------------------------------------------------------------
    # Container timeout
    # -------------------------------------------------------------------------

    test "raises ContainerTimeoutError and marks post failed when container times out" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      # Provide a client that succeeds for quota + container creation, but
      # stub wait_until_finished! to raise immediately so the test doesn't block.
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| { "id" => "cont_001" } }
      @publisher.instance_variable_set(:@client, mock_client)

      timeout_error = Instagram::ContainerTimeoutError.new("Video container did not finish in time")
      @publisher.stub(:wait_until_finished!, ->(_cid, **) { raise timeout_error }) do
        assert_raises(Instagram::ContainerTimeoutError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end

    # -------------------------------------------------------------------------
    # Attached audio
    # -------------------------------------------------------------------------

    test "forwards audio_configuration when platform_payload requests a track" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @video_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: {
          "audio_configuration" => { "audio_id" => "587784541076604", "audio_volume" => 80 }
        }
      )

      captured_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        path.end_with?("/media_publish") ? { "id" => "m1" } : (captured_params = body; { "id" => "c1" })
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_equal(
        { "audio_id" => "587784541076604", "audio_volume" => 80 },
        JSON.parse(captured_params[:audio_configuration])
      )
    end

    test "accepts a bare audio_id as shorthand for audio_configuration" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @video_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "audio_id" => "587784541076604" }
      )

      captured_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        path.end_with?("/media_publish") ? { "id" => "m1" } : (captured_params = body; { "id" => "c1" })
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_equal({ "audio_id" => "587784541076604" }, JSON.parse(captured_params[:audio_configuration]))
    end

    test "omits audio_configuration when no track is attached" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
      )

      captured_params = nil
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        path.end_with?("/media_publish") ? { "id" => "m1" } : (captured_params = body; { "id" => "c1" })
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_not captured_params.key?(:audio_configuration)
    end
  end
end
