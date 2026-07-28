# frozen_string_literal: true

require "test_helper"

module TikTok
  class ApiClientTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def setup
      @user   = users(:one)
      @client = TikTok::ApiClient.new(@user)
    end

    # Build a Faraday connection backed by the test adapter for the v2 API base.
    def json_connection(&block)
      stubs = Faraday::Adapter::Test::Stubs.new(&block)
      Faraday.new do |f|
        f.request  :json
        f.response :json, content_type: /\bjson$/
        f.adapter  :test, stubs
      end
    end

    def stub_post(path, body, status: 200)
      json_connection do |stub|
        stub.post(path) { [ status, { "Content-Type" => "application/json" }, body.to_json ] }
      end
    end

    def error_body(code, message: "boom")
      { "error" => { "code" => code, "message" => message, "log_id" => "log_123" } }
    end

    # -------------------------------------------------------------------------
    # Success detection — error.code == "ok", not the absence of "error"
    # -------------------------------------------------------------------------

    test "post treats error.code == ok as success and returns the parsed body" do
      body = { "data" => { "publish_id" => "v_pub_001" }, "error" => { "code" => "ok", "message" => "", "log_id" => "log_1" } }

      @client.stub(:connection, stub_post("post/publish/video/init/", body)) do
        result = @client.post("post/publish/video/init/", source_info: { source: "FILE_UPLOAD" })
        assert_equal "v_pub_001", result.dig("data", "publish_id")
      end
    end

    test "post succeeds when the response carries no error object at all" do
      body = { "data" => { "status" => "PUBLISH_COMPLETE" } }

      @client.stub(:connection, stub_post("post/publish/status/fetch/", body)) do
        result = @client.post("post/publish/status/fetch/", publish_id: "v_pub_001")
        assert_equal "PUBLISH_COMPLETE", result.dig("data", "status")
      end
    end

    test "get sends the bearer token and returns the parsed body" do
      captured_auth = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("user/info/") do |env|
          captured_auth = env.request_headers["Authorization"]
          [ 200, { "Content-Type" => "application/json" }, { "data" => { "user" => {} } }.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json, content_type: /\bjson$/; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        @client.get("user/info/", fields: "open_id")
      end

      assert_equal "Bearer #{@user.tiktok_access_token}", captured_auth
    end

    # -------------------------------------------------------------------------
    # Error classification
    # -------------------------------------------------------------------------

    test "post raises RateLimitError for rate_limit_exceeded" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("rate_limit_exceeded"), status: 429)) do
        error = assert_raises(TikTok::RateLimitError) { @client.post("post/publish/video/init/") }
        assert_equal "rate_limit_exceeded", error.code
        assert_equal "log_123", error.log_id
      end
    end

    test "post raises RateLimitError for spam_risk_too_many_posts" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("spam_risk_too_many_posts"), status: 403)) do
        assert_raises(TikTok::RateLimitError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises TokenExpiredError for access_token_invalid" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("access_token_invalid"), status: 401)) do
        assert_raises(TikTok::TokenExpiredError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises TokenExpiredError for scope_not_authorized" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("scope_not_authorized"), status: 401)) do
        assert_raises(TikTok::TokenExpiredError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises the non-retryable PermanentError for url_ownership_unverified" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("url_ownership_unverified"), status: 403)) do
        error = assert_raises(TikTok::PermanentError) { @client.post("post/publish/video/init/") }
        assert_not_kind_of TikTok::ApiError, error, "PermanentError must not be retried as an ApiError"
      end
    end

    test "post raises PermanentError for privacy_level_option_mismatch" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("privacy_level_option_mismatch"), status: 403)) do
        assert_raises(TikTok::PermanentError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises PermanentError for unaudited_client_can_only_post_to_private_accounts" do
      body = error_body("unaudited_client_can_only_post_to_private_accounts")
      @client.stub(:connection, stub_post("post/publish/video/init/", body, status: 403)) do
        assert_raises(TikTok::PermanentError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises the retryable ApiError for an unrecognised error code" do
      @client.stub(:connection, stub_post("post/publish/video/init/", error_body("something_new"), status: 400)) do
        assert_raises(TikTok::ApiError) { @client.post("post/publish/video/init/") }
      end
    end

    test "post raises ApiError on an HTTP error with no usable error object" do
      @client.stub(:connection, stub_post("post/publish/video/init/", { "message" => "gateway down" }, status: 502)) do
        assert_raises(TikTok::ApiError) { @client.post("post/publish/video/init/") }
      end
    end

    # -------------------------------------------------------------------------
    # Token handling
    # -------------------------------------------------------------------------

    test "raises TokenExpiredError when the user has neither access nor refresh token" do
      @user.tiktok_access_token  = nil
      @user.tiktok_refresh_token = nil

      assert_raises(TikTok::TokenExpiredError) { @client.get("user/info/") }
    end

    test "refreshes the access token when it is about to expire" do
      @user.update!(tiktok_token_expires_at: 1.minute.from_now)

      refreshed = false
      refresher = Object.new
      refresher.define_singleton_method(:refresh_access_token!) { refreshed = true }

      TikTok::AuthService.stub(:new, refresher) do
        @client.stub(:connection, stub_post("post/publish/status/fetch/", { "data" => {} })) do
          @client.post("post/publish/status/fetch/")
        end
      end

      assert refreshed, "expected the client to refresh a near-expiry token"
    end

    test "does not refresh a token that is still comfortably valid" do
      @user.update!(tiktok_token_expires_at: 20.hours.from_now)

      TikTok::AuthService.stub(:new, ->(_) { raise "should not refresh" }) do
        @client.stub(:connection, stub_post("post/publish/status/fetch/", { "data" => {} })) do
          assert_nothing_raised { @client.post("post/publish/status/fetch/") }
        end
      end
    end

    # -------------------------------------------------------------------------
    # #upload_chunk
    # -------------------------------------------------------------------------

    test "upload_chunk sends Content-Range and returns the HTTP status" do
      captured = {}
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("https://upload.tiktokapis.com/chunk") do |env|
          captured = env.request_headers.dup.merge("body" => env.body)
          [ 206, {}, "" ]
        end
      end
      conn = Faraday.new { |f| f.adapter :test, stubs }

      status = @client.stub(:upload_connection, conn) do
        @client.upload_chunk("https://upload.tiktokapis.com/chunk", "abcdefgh",
          content_type: "video/mp4", first_byte: 0, last_byte: 7, total_bytes: 16)
      end

      assert_equal 206, status
      assert_equal "bytes 0-7/16", captured["Content-Range"]
      assert_equal "video/mp4",    captured["Content-Type"]
      assert_equal "8",            captured["Content-Length"]
      assert_equal "abcdefgh",     captured["body"]
    end

    test "upload_chunk raises UploadError when the chunk is rejected" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.put("https://upload.tiktokapis.com/chunk") { [ 400, {}, "bad range" ] }
      end
      conn = Faraday.new { |f| f.adapter :test, stubs }

      @client.stub(:upload_connection, conn) do
        assert_raises(TikTok::UploadError) do
          @client.upload_chunk("https://upload.tiktokapis.com/chunk", "abc",
            content_type: "video/mp4", first_byte: 0, last_byte: 2, total_bytes: 3)
        end
      end
    end
  end
end
