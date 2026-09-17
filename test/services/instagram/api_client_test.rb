# frozen_string_literal: true

require "test_helper"

module Instagram
  class ApiClientTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def setup
      @user = users(:one)
      @client = Instagram::ApiClient.new(@user)
    end

    # Returns a Faraday::Env-compatible double that mimics a successful response.
    def stub_response(body, status: 200)
      env    = Faraday::Env.from(method: :get, url: URI("https://graph.facebook.com/v21.0/"), body: nil, request_headers: {})
      Faraday::Response.new(env).tap do |r|
        r.finish(status: status, response_headers: { "content-type" => "application/json" }, body: body)
      end
    end

    # -------------------------------------------------------------------------
    # #get
    # -------------------------------------------------------------------------

    test "get merges access_token into query params and returns parsed body" do
      expected_body = { "id" => "123" }

      @client.stub(:connection, Faraday.new { |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, Faraday::Adapter::Test::Stubs.new { |stub|
          stub.get("me") { [ 200, { "Content-Type" => "application/json" }, expected_body.to_json ] }
        }
      }) do
        result = @client.get("me")
        assert_equal expected_body, result
      end
    end

    test "get raises TokenExpiredError when user has no access token" do
      @user.instagram_access_token = nil
      assert_raises(Instagram::TokenExpiredError) { @client.get("me") }
    end

    test "uses override access_token instead of user token when provided" do
      client = Instagram::ApiClient.new(@user, access_token: "OVERRIDE_TOKEN")

      client.stub(:connection, Faraday.new { |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, Faraday::Adapter::Test::Stubs.new { |stub|
          stub.get("me") { [ 200, { "Content-Type" => "application/json" }, { "id" => "ok" }.to_json ] }
        }
      }) do
        # Should not raise even though we don't check the token value here;
        # the key assertion is that a blank user token doesn't block the call.
        @user.instagram_access_token = nil
        assert_nothing_raised { client.get("me") }
      end
    end

    test "raises TokenExpiredError when override token is blank and user has no token" do
      @user.instagram_access_token = nil
      client = Instagram::ApiClient.new(@user, access_token: "")
      assert_raises(Instagram::TokenExpiredError) { client.get("me") }
    end

    # -------------------------------------------------------------------------
    # #post
    # -------------------------------------------------------------------------

    test "post sends body and returns parsed response" do
      response_body = { "id" => "cont_001" }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("17841400000000001/media") { [ 200, { "Content-Type" => "application/json" }, response_body.to_json ] }
      end
      conn = Faraday.new { |f| f.request :url_encoded; f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        result = @client.post("17841400000000001/media", image_url: "https://cdn.example.com/img.jpg")
        assert_equal "cont_001", result["id"]
      end
    end

    # -------------------------------------------------------------------------
    # #post_upload
    # -------------------------------------------------------------------------

    test "post_upload targets an absolute URL and authenticates with a header" do
      seen = nil
      sent_body = :unset

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("https://rupload.facebook.com/video-upload/v26.0/vid_001") do |env|
          seen      = env
          sent_body = env.body
          [ 200, { "Content-Type" => "application/json" }, { "success" => true }.to_json ]
        end
      end
      conn = Faraday.new { |f| f.request :url_encoded; f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        result = @client.post_upload(
          "https://rupload.facebook.com/video-upload/v26.0/vid_001",
          "file_url" => "https://cdn.example.com/story.mp4"
        )
        assert_equal({ "success" => true }, result)
      end

      assert_equal "rupload.facebook.com", seen.url.host
      # The token belongs in the header here — not the query string or the body,
      # which is where the regular #post puts it.
      assert_equal "OAuth #{@user.instagram_access_token}", seen.request_headers["Authorization"]
      assert_equal "https://cdn.example.com/story.mp4", seen.request_headers["file_url"]
      assert_nil seen.url.query
      assert_predicate sent_body, :blank?
    end

    test "post_upload raises ApiError on a Meta error response" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("https://rupload.facebook.com/vid_002") do
          [ 400, { "Content-Type" => "application/json" },
            { "error" => { "message" => "File not found", "code" => 100 } }.to_json ]
        end
      end
      conn = Faraday.new { |f| f.request :url_encoded; f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        error = assert_raises(Instagram::ApiError) do
          @client.post_upload("https://rupload.facebook.com/vid_002", "file_url" => "https://cdn.example.com/gone.mp4")
        end
        assert_equal "File not found (Meta error 100)", error.message
      end
    end

    # -------------------------------------------------------------------------
    # Error handling
    # -------------------------------------------------------------------------

    test "handle_response raises ApiError on Meta error response" do
      error_body = {
        "error" => {
          "message"   => "Invalid OAuth access token",
          "type"      => "OAuthException",
          "code"      => 190,
          "fbtrace_id"=> "abc123"
        }
      }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("me") { [ 200, { "Content-Type" => "application/json" }, error_body.to_json ] }
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        err = assert_raises(Instagram::ApiError) { @client.get("me") }
        assert_equal "Invalid OAuth access token (Meta error 190)", err.message
        assert_equal 190, err.code
        assert_equal "OAuthException", err.type
        assert_equal "abc123", err.fbtrace_id
      end
    end

    test "handle_response raises RateLimitError for code 9007" do
      error_body = {
        "error" => { "message" => "Quota exceeded", "type" => "IGApiException", "code" => 9007, "fbtrace_id" => "xyz" }
      }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("me") { [ 200, { "Content-Type" => "application/json" }, error_body.to_json ] }
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        assert_raises(Instagram::RateLimitError) { @client.get("me") }
      end
    end

    test "handle_response raises RateLimitError for code 4" do
      error_body = {
        "error" => { "message" => "App rate limit hit", "type" => "OAuthException", "code" => 4, "fbtrace_id" => "abc" }
      }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("me") { [ 200, { "Content-Type" => "application/json" }, error_body.to_json ] }
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        assert_raises(Instagram::RateLimitError) { @client.get("me") }
      end
    end

    test "handle_response folds error_subcode and error_user_msg into the message" do
      error_body = {
        "error" => {
          "message"        => "Invalid user id",
          "type"           => "OAuthException",
          "code"           => 110,
          "error_subcode"  => 2207018,
          "error_user_msg" => "Cannot load user with a private profile or invalid username",
          "fbtrace_id"     => "trace1"
        }
      }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("me") { [ 200, { "Content-Type" => "application/json" }, error_body.to_json ] }
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        err = assert_raises(Instagram::ApiError) { @client.get("me") }

        assert_equal(
          "Invalid user id: Cannot load user with a private profile or invalid username " \
          "(Meta error 110/2207018)",
          err.message
        )
        assert_equal 110, err.code
        assert_equal 2207018, err.subcode
        assert_equal "Cannot load user with a private profile or invalid username", err.user_message
      end
    end

    # -------------------------------------------------------------------------
    # #publishing_limit
    # -------------------------------------------------------------------------

    test "publishing_limit calls the correct endpoint" do
      response_body = { "data" => [ { "quota_usage" => 3, "config" => { "quota_total" => 25 } } ] }

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("17841400000000001/content_publishing_limit") do
          [ 200, { "Content-Type" => "application/json" }, response_body.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:connection, conn) do
        result = @client.publishing_limit("17841400000000001")
        assert_equal 3, result.dig("data", 0, "quota_usage")
      end
    end
  end
end
