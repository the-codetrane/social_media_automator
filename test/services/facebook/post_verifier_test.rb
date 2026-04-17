# frozen_string_literal: true

require "test_helper"

module Facebook
  class PostVerifierTest < ActiveSupport::TestCase
    def setup
      @user     = users(:one)
      @verifier = Facebook::PostVerifier.new(@user)
      @page_id  = @user.instagram_page_id
    end

    test "verify fetches page token then GETs post by id with expected fields" do
      post_id   = "123456789_987654321"
      permalink = "https://www.facebook.com/permalink/123"
      page_id   = @page_id
      call_log  = []

      Instagram::ApiClient.stub(:new, ->(_user, **opts) {
        client = Object.new
        client.define_singleton_method(:get) do |path, params = {}|
          call_log << { path: path, params: params }
          if path == page_id
            { "access_token" => "PAGE_TOKEN" }
          else
            { "id" => post_id, "permalink_url" => permalink }
          end
        end
        client
      }) do
        result = @verifier.verify(post_id)
        assert_equal permalink, result["permalink_url"]
      end

      page_token_call = call_log.find { |c| c[:path] == page_id }
      verify_call     = call_log.find { |c| c[:path] == post_id }

      assert_not_nil page_token_call
      assert_not_nil verify_call
      assert_includes verify_call[:params][:fields], "permalink_url"
    end

    test "raises ApiError when user has no page_id" do
      @user.instagram_page_id = nil
      assert_raises(Instagram::ApiError) { Facebook::PostVerifier.new(@user) }
    end

    test "raises ApiError when page token fetch returns blank" do
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) { |*_| { "access_token" => nil } }
        client
      }) do
        assert_raises(Instagram::ApiError) { @verifier.verify("any_id") }
      end
    end

    test "propagates ApiError from the post fetch" do
      page_id = @page_id
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) {
        client = Object.new
        client.define_singleton_method(:get) do |path, _params = {}|
          if path == page_id
            { "access_token" => "PAGE_TOKEN" }
          else
            raise Instagram::ApiError.new("Does not exist", code: 100)
          end
        end
        client
      }) do
        err = assert_raises(Instagram::ApiError) { @verifier.verify("missing_post") }
        assert_equal 100, err.code
      end
    end
  end
end
