# frozen_string_literal: true

require "test_helper"

module Instagram
  class CarouselPublisherTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user      = users(:one)
      @publisher = Instagram::CarouselPublisher.new(@user)
      @ig_id     = @user.instagram_user_id

      @image_1 = media_assets(:sample_image)
      @image_2 = media_assets(:sample_image_2)
    end

    # Replaces the publisher's internal ApiClient with a lightweight double.
    # +get_responses+  – Hash of path → response body for GET calls
    # +post_responses+ – Hash of path → response body for POST calls
    def with_stubbed_client(get_responses: {}, post_responses: {})
      mock_client = Object.new

      mock_client.define_singleton_method(:get) do |path, _params = {}|
        get_responses.fetch(path) { raise "Unexpected GET #{path}" }
      end

      mock_client.define_singleton_method(:post) do |path, _body = {}|
        post_responses.fetch(path) { raise "Unexpected POST #{path}" }
      end

      mock_client.define_singleton_method(:publishing_limit) do |_ig_user_id|
        { "data" => [ { "quota_usage" => 1, "config" => { "quota_total" => 25 } } ] }
      end

      @publisher.instance_variable_set(:@client, mock_client)
      yield @publisher
    end

    # -------------------------------------------------------------------------
    # #publish — happy path
    # -------------------------------------------------------------------------

    test "publish creates child containers, parent carousel container, and publishes" do
      child_id_1 = "cont_child_001"
      child_id_2 = "cont_child_002"
      parent_id  = "cont_parent_001"
      media_id   = "ig_media_carousel_001"

      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        caption:          "Carousel caption",
        hashtags:         "#photo",
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, @image_2.id ] }
      )

      post_call_count = 0

      with_stubbed_client(
        get_responses: {
          child_id_1 => { "status_code" => "FINISHED" },
          child_id_2 => { "status_code" => "FINISHED" },
          parent_id  => { "status_code" => "FINISHED" }
        },
        post_responses: {
          "#{@ig_id}/media"         => proc { post_call_count += 1; { "id" => [ child_id_1, child_id_2, parent_id ][post_call_count - 1] } },
          "#{@ig_id}/media_publish" => { "id" => media_id }
        }
      ) do |publisher|
        # Make post_responses use a simple sequential queue instead.
        container_ids = [ child_id_1, child_id_2, parent_id ]
        call_index    = 0

        mock_client = Object.new
        mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 1, "config" => { "quota_total" => 25 } } ] } }
        mock_client.define_singleton_method(:get) do |path, _params = {}|
          { "status_code" => "FINISHED" }
        end
        mock_client.define_singleton_method(:post) do |path, _body = {}|
          if path.end_with?("/media_publish")
            { "id" => media_id }
          else
            id = container_ids[call_index]
            call_index += 1
            { "id" => id }
          end
        end

        publisher.instance_variable_set(:@client, mock_client)

        result = publisher.publish(post)

        assert_equal media_id, result
        post.reload
        assert post.published?
        assert_equal media_id, post.external_post_id
        assert_not_nil post.published_at
        assert_equal media_id, post.platform_payload["ig_media_id"]
        assert_equal 2, post.platform_payload["carousel_item_count"]
      end
    end

    test "publish joins caption and hashtags with double newline" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        caption:          "Nice pic",
        hashtags:         "#photo #art",
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, @image_2.id ] }
      )

      captured_params = nil
      container_ids   = [ "c1", "c2", "parent" ]
      call_index      = 0

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        if path.end_with?("/media_publish")
          { "id" => "media_999" }
        else
          captured_params = body if body[:media_type] == "CAROUSEL"
          id = container_ids[call_index]
          call_index += 1
          { "id" => id }
        end
      end

      @publisher.instance_variable_set(:@client, mock_client)
      @publisher.publish(post)

      assert_not_nil captured_params
      assert_equal "Nice pic\n\n#photo #art", captured_params[:caption]
    end

    # -------------------------------------------------------------------------
    # #publish — validation errors
    # -------------------------------------------------------------------------

    test "raises ArgumentError when fewer than 2 items" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id ] }
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(ArgumentError) { @publisher.publish(post) }
        assert_match(/at least 2/i, err.message)
      end
    end

    test "raises ArgumentError when more than 10 items" do
      # Create 11 image assets inline for this boundary test.
      assets = (1..11).map do |i|
        MediaAsset.create!(
          external_id:     "extra_img_#{i}",
          external_name:   "extra_#{i}.jpg",
          media_type:      :image,
          status:          :processed,
          first_seen_at:   Time.current,
          raw_metadata:    { "public_url" => "https://cdn.example.com/extra_#{i}.jpg" }.to_json
        )
      end

      post = PlannedPost.create!(
        user:             @user,
        media_asset:      assets.first,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => assets.map(&:id) }
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(ArgumentError) { @publisher.publish(post) }
        assert_match(/at most 10/i, err.message)
      end
    end

    test "raises ArgumentError when a non-image asset is included" do
      video = media_assets(:sample_video)

      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, video.id ] }
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(ArgumentError) { @publisher.publish(post) }
        assert_match(/must be images/i, err.message)
        assert_match(video.id.to_s, err.message)
      end
    end

    test "raises ApiError when an asset has no public URL" do
      no_url_asset = media_assets(:sample_image_no_url)

      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, no_url_asset.id ] }
      )

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/no public URL/i, err.message)
      end
    end

    test "marks post as failed and re-raises when an Instagram::Error occurs" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, @image_2.id ] }
      )

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| raise Instagram::ApiError, "upstream failure" }
      mock_client.define_singleton_method(:get)  { |*_| { "status_code" => "FINISHED" } }

      @publisher.instance_variable_set(:@client, mock_client)

      assert_raises(Instagram::ApiError) { @publisher.publish(post) }
      assert post.reload.failed?
    end

    # -------------------------------------------------------------------------
    # Quota check
    # -------------------------------------------------------------------------

    test "raises RateLimitError when publishing quota is exhausted" do
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, @image_2.id ] }
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
        user:             @user,
        media_asset:      @image_1,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ @image_1.id, @image_2.id ] }
      )

      # Provide a client that succeeds for quota + container creation, but
      # stub wait_until_finished! to raise immediately so the test doesn't block.
      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:post) { |*_| { "id" => "cont_001" } }
      @publisher.instance_variable_set(:@client, mock_client)

      timeout_error = Instagram::ContainerTimeoutError.new("Container did not finish in time")
      @publisher.stub(:wait_until_finished!, ->(_cid, **) { raise timeout_error }) do
        assert_raises(Instagram::ContainerTimeoutError) { @publisher.publish(post) }
      end

      assert post.reload.failed?
    end
  end
end
