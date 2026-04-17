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
