# frozen_string_literal: true

require "test_helper"

module Instagram
  class StoriesPublisherTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user      = users(:one)
      @publisher = Instagram::StoriesPublisher.new(@user)
      @ig_id     = @user.instagram_user_id

      @image_asset = media_assets(:sample_image)
      @video_asset = media_assets(:sample_video)
    end

    # Replace the publisher's internal ApiClient with a lightweight double.
    def stub_client(container_id: "cont_story_001", media_id: "ig_story_001",
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
    # #publish — happy path with image
    # -------------------------------------------------------------------------

    test "publish creates a STORIES container with image_url, polls until FINISHED, and publishes" do
      container_id = "cont_story_img_001"
      media_id     = "ig_story_img_001"

      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @image_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil,
        caption:      "This caption is ignored for stories"
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
      assert_equal "STORIES", post.platform_payload["media_type"]
      assert_equal container_id, post.platform_payload["container_id"]

      # Verify the Meta API params
      assert_not_nil captured_media_params
      assert_equal "STORIES", captured_media_params[:media_type]
      assert_equal "https://cdn.example.com/sunset.jpg", captured_media_params[:image_url]
      # Stories do NOT include caption
      assert_nil captured_media_params[:caption]
    end

    # -------------------------------------------------------------------------
    # #publish — happy path with video
    # -------------------------------------------------------------------------

    test "publish creates a STORIES container with video_url for video assets" do
      container_id = "cont_story_vid_001"
      media_id     = "ig_story_vid_001"

      post = PlannedPost.create!(
        user:         @user,
        media_asset:  @video_asset,
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil
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

      # Verify video_url is used instead of image_url
      assert_not_nil captured_media_params
      assert_equal "STORIES", captured_media_params[:media_type]
      assert_equal "https://cdn.example.com/reel.mp4", captured_media_params[:video_url]
      assert_nil captured_media_params[:image_url]
    end

    # -------------------------------------------------------------------------
    # Rate limit handling
    # -------------------------------------------------------------------------

    test "publish raises RateLimitError when quota is exhausted" do
      stub_client(quota_usage: 25, quota_total: 25)

      post = PlannedPost.create!(
        user:        @user,
        media_asset: @image_asset,
        platform:    :instagram,
        status:      :draft
      )

      assert_raises(Instagram::RateLimitError) do
        @publisher.publish(post)
      end
    end

    # -------------------------------------------------------------------------
    # Container error handling
    # -------------------------------------------------------------------------

    test "publish raises ApiError when container enters ERROR status" do
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| { "id" => "cont_err" } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "ERROR", "status" => "Upload failed" } }

      @publisher.instance_variable_set(:@client, mock_client)

      post = PlannedPost.create!(
        user:        @user,
        media_asset: @image_asset,
        platform:    :instagram,
        status:      :draft
      )

      error = assert_raises(Instagram::ApiError) do
        @publisher.publish(post)
      end

      assert_match(/ERROR/, error.message)
      post.reload
      assert post.failed?
    end

    # -------------------------------------------------------------------------
    # Missing public URL
    # -------------------------------------------------------------------------

    test "publish raises ApiError when media asset has no public URL" do
      asset_without_url = MediaAsset.create!(
        external_id:   "no_url_#{SecureRandom.hex(4)}",
        media_type:    :image,
        status:        :processed,
        first_seen_at: Time.current,
        raw_metadata:  {}  # No public_url
      )

      post = PlannedPost.create!(
        user:        @user,
        media_asset: asset_without_url,
        platform:    :instagram,
        status:      :draft
      )

      stub_client

      error = assert_raises(Instagram::ApiError) do
        @publisher.publish(post)
      end

      assert_match(/no public URL/, error.message)
    end

    # -------------------------------------------------------------------------
    # Container timeout
    # -------------------------------------------------------------------------

    test "publish raises ContainerTimeoutError when container does not finish in time" do
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| { "id" => "cont_timeout" } }
      # Always return IN_PROGRESS
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "IN_PROGRESS" } }

      @publisher.instance_variable_set(:@client, mock_client)

      # Replace the 5s real sleep between polls with virtual time travel so
      # the deadline can be reached in zero wall-clock time.
      test_case = self
      @publisher.define_singleton_method(:sleep) { |seconds| test_case.travel(seconds.seconds) }

      freeze_time do
        error = assert_raises(Instagram::ContainerTimeoutError) do
          @publisher.send(:wait_until_finished!, "cont_timeout", timeout: 1)
        end

        assert_match(/did not finish processing/, error.message)
      end
    end
  end
end
