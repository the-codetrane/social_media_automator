# frozen_string_literal: true

require "test_helper"

module Facebook
  class PagePublisherTest < ActiveSupport::TestCase
    def setup
      @user      = users(:one)
      @post      = planned_posts(:facebook_draft_post)
      @publisher = Facebook::PagePublisher.new(@user)
      @page_id   = @user.instagram_page_id
    end

    # Stubs both the page-token fetch (GET /{page_id}) and one POST call.
    def with_stubbed_client(page_token: "PAGE_TOKEN", post_path:, post_response:)
      call_count = 0

      mock_client_class = ->(user, access_token: nil) {
        client = Object.new
        client.define_singleton_method(:get) do |path, _params = {}|
          raise "Unexpected GET #{path}" unless path == @page_id
          { "access_token" => page_token }
        end
        client.define_singleton_method(:post) do |path, _body = {}|
          raise "Unexpected POST #{path}" unless path == post_path
          post_response
        end
        client
      }

      Instagram::ApiClient.stub(:new, mock_client_class) do
        yield
      end
    end

    # -------------------------------------------------------------------------
    # #publish — photo
    # -------------------------------------------------------------------------

    test "publish posts photo to page photos endpoint and updates post" do
      page_id = @page_id
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => "PAGE_TOKEN" } }
        client.define_singleton_method(:post) do |path, _body = {}|
          if path == "#{page_id}/photos"
            { "id" => "photo_001", "post_id" => "fb_post_001" }
          else
            raise "Unexpected POST #{path}"
          end
        end
        client
      }) do
        post_id = @publisher.publish(@post)
        assert_equal "fb_post_001", post_id
        assert @post.reload.published?
        assert_equal "fb_post_001", @post.external_post_id
        assert_not_nil @post.published_at
      end
    end

    test "publish posts video to page videos endpoint" do
      video_post = PlannedPost.create!(
        user:         @user,
        media_asset:  media_assets(:sample_video),
        platform:     :facebook,
        status:       :draft,
        caption:      "Watch this!",
        hashtags:     "#video"
      )

      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => "PAGE_TOKEN" } }
        client.define_singleton_method(:post) do |path, _body = {}|
          raise "Expected videos endpoint, got #{path}" unless path.end_with?("/videos")
          { "id" => "fb_video_001" }
        end
        client
      }) do
        post_id = @publisher.publish(video_post)
        assert_equal "fb_video_001", post_id
        assert video_post.reload.published?
      end
    end

    # -------------------------------------------------------------------------
    # #publish — carousel
    # -------------------------------------------------------------------------

    # Records every POST so a test can assert on the two-step carousel flow.
    def stub_recording_client(calls, responses)
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => "PAGE_TOKEN" } }
        client.define_singleton_method(:post) do |path, body = {}|
          calls << [ path, body ]
          responses.call(path, body)
        end
        client
      }) do
        yield
      end
    end

    def facebook_carousel_post(asset_ids, **overrides)
      PlannedPost.create!({
        user:             @user,
        media_asset:      MediaAsset.find(asset_ids.first),
        platform:         :facebook,
        status:           :draft,
        caption:          "Two shots",
        hashtags:         "#carousel",
        platform_payload: { "carousel_asset_ids" => asset_ids }
      }.merge(overrides))
    end

    test "publish uploads each carousel image unpublished then attaches them to one feed post" do
      image_1 = media_assets(:sample_image)
      image_2 = media_assets(:sample_image_2)
      post    = facebook_carousel_post([ image_1.id, image_2.id ])
      calls   = []

      photo_ids = %w[ph_1 ph_2]
      responses = ->(path, _body) {
        if path.end_with?("/photos")
          { "id" => photo_ids.shift }
        else
          { "id" => "fb_carousel_001" }
        end
      }

      stub_recording_client(calls, responses) do
        assert_equal "fb_carousel_001", @publisher.publish(post)
      end

      photo_calls = calls.select { |path, _| path.end_with?("/photos") }
      assert_equal 2, photo_calls.size
      assert_equal [ image_1.public_url, image_2.public_url ], photo_calls.map { |_, body| body[:url] }
      photo_calls.each do |_, body|
        assert_equal "false", body[:published]
        assert_equal "true",  body[:temporary]
      end

      feed_path, feed_body = calls.last
      assert_equal "#{@page_id}/feed", feed_path
      assert_equal({ "media_fbid" => "ph_1" }, JSON.parse(feed_body["attached_media[0]"]))
      assert_equal({ "media_fbid" => "ph_2" }, JSON.parse(feed_body["attached_media[1]"]))
      assert_includes feed_body[:message], "Two shots"

      post.reload
      assert post.published?
      assert_equal "fb_carousel_001", post.external_post_id
      assert_equal 2, post.platform_payload["carousel_item_count"]
      assert_equal %w[ph_1 ph_2], post.platform_payload["carousel_media_fbids"]
      # The original ids survive the payload merge.
      assert_equal [ image_1.id, image_2.id ], post.platform_payload["carousel_asset_ids"]
    end

    test "publish preserves carousel ordering from carousel_asset_ids" do
      image_1 = media_assets(:sample_image)
      image_2 = media_assets(:sample_image_2)
      post    = facebook_carousel_post([ image_2.id, image_1.id ])
      calls   = []

      counter   = 0
      responses = ->(path, _body) {
        if path.end_with?("/photos")
          counter += 1
          { "id" => "ph_#{counter}" }
        else
          { "id" => "fb_carousel_002" }
        end
      }

      stub_recording_client(calls, responses) do
        @publisher.publish(post)
      end

      urls = calls.select { |path, _| path.end_with?("/photos") }.map { |_, body| body[:url] }
      assert_equal [ image_2.public_url, image_1.public_url ], urls
    end

    test "publish treats a single carousel asset id as a plain photo post" do
      post  = facebook_carousel_post([ media_assets(:sample_image).id ])
      calls = []

      stub_recording_client(calls, ->(_path, _body) { { "id" => "ph", "post_id" => "fb_single" } }) do
        assert_equal "fb_single", @publisher.publish(post)
      end

      assert_equal 1, calls.size
      assert_equal "#{@page_id}/photos", calls.first.first
      assert_nil calls.first.last[:published]
    end

    test "publish raises when a carousel contains a video" do
      post = facebook_carousel_post([ media_assets(:sample_image).id, media_assets(:sample_video).id ])

      stub_recording_client([], ->(_path, _body) { { "id" => "x" } }) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/images only/, error.message)
      end

      assert post.reload.draft?
    end

    test "publish raises when a carousel exceeds ten photos" do
      assets = 11.times.map do |i|
        MediaAsset.create!(
          external_id:   "fb_carousel_asset_#{i}",
          media_type:    :image,
          status:        :processed,
          first_seen_at: 1.day.ago,
          raw_metadata:  { "public_url" => "https://cdn.example.com/#{i}.jpg" }.to_json
        )
      end
      post = facebook_carousel_post(assets.map(&:id))

      stub_recording_client([], ->(_path, _body) { { "id" => "x" } }) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/at most 10 photos/, error.message)
      end
    end

    test "publish skips carousel asset ids whose MediaAsset no longer exists" do
      image_1 = media_assets(:sample_image)
      image_2 = media_assets(:sample_image_2)
      post    = facebook_carousel_post([ image_1.id, image_2.id ])
      post.update!(platform_payload: { "carousel_asset_ids" => [ image_1.id, 999_999, image_2.id ] })
      calls = []

      counter   = 0
      responses = ->(path, _body) {
        if path.end_with?("/photos")
          counter += 1
          { "id" => "ph_#{counter}" }
        else
          { "id" => "fb_carousel_003" }
        end
      }

      stub_recording_client(calls, responses) do
        assert_equal "fb_carousel_003", @publisher.publish(post)
      end

      assert_equal 2, calls.count { |path, _| path.end_with?("/photos") }
      assert_equal 2, post.reload.platform_payload["carousel_item_count"]
    end

    test "publish raises when a carousel asset has no public url" do
      no_url = MediaAsset.create!(
        external_id:   "fb_carousel_no_url",
        media_type:    :image,
        status:        :processed,
        first_seen_at: 1.day.ago
      )
      post = facebook_carousel_post([ media_assets(:sample_image).id, no_url.id ])

      stub_recording_client([], ->(_path, _body) { { "id" => "ph" } }) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/no public URL/, error.message)
      end
    end

    # -------------------------------------------------------------------------
    # Error cases
    # -------------------------------------------------------------------------

    test "raises ApiError when user has no page_id" do
      @user.instagram_page_id = nil
      assert_raises(Instagram::ApiError) { Facebook::PagePublisher.new(@user) }
    end

    test "raises ApiError when page token fetch returns blank" do
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => nil } }
        client
      }) do
        assert_raises(Instagram::ApiError) { @publisher.publish(@post) }
      end
    end

    test "does not mark post failed when ApiError is raised (job handles that)" do
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => nil } }
        client
      }) do
        assert_raises(Instagram::ApiError) { @publisher.publish(@post) }
        assert_not @post.reload.failed?
      end
    end

    # -------------------------------------------------------------------------
    # Caption building
    # -------------------------------------------------------------------------

    test "publish combines caption and hashtags with double newline" do
      posted_message = nil

      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => "TOKEN" } }
        client.define_singleton_method(:post) do |_path, body = {}|
          posted_message = body[:message] || body["message"]
          { "id" => "001", "post_id" => "p_001" }
        end
        client
      }) do
        @publisher.publish(@post)
      end

      assert_includes posted_message, @post.caption
      assert_includes posted_message, @post.hashtags
    end
  end
end
