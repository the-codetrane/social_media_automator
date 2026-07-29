# frozen_string_literal: true

require "test_helper"

module TikTok
  class AuthServiceTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user    = users(:two)   # starts with no TikTok credentials
      @service = TikTok::AuthService.new(@user)
    end

    # Point the service's OAuth connection at the Faraday test adapter.
    def with_token_response(body, status: 200, &block)
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post(TikTok::AuthService::TOKEN_URL) { [ status, { "Content-Type" => "application/json" }, body.to_json ] }
        stub.post(TikTok::AuthService::REVOKE_URL) { [ 200, { "Content-Type" => "application/json" }, "{}" ] }
      end
      conn = Faraday.new do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, stubs
      end

      @service.stub(:token_connection, conn, &block)
    end

    # exchange_code labels the connection via creator_info; keep it off the network.
    def with_creator_info(username: "cainandco", &block)
      info = Object.new
      info.define_singleton_method(:query) { { "creator_username" => username } }
      TikTok::CreatorInfoService.stub(:new, info, &block)
    end

    def token_payload(overrides = {})
      {
        "access_token"       => "act.new_token",
        "expires_in"         => 86_400,
        "refresh_token"      => "rft.new_refresh",
        "refresh_expires_in" => 31_536_000,
        "open_id"            => "open_id_abc",
        "scope"              => "user.info.basic,video.publish",
        "token_type"         => "Bearer"
      }.merge(overrides)
    end

    # -------------------------------------------------------------------------
    # #build_auth_url
    # -------------------------------------------------------------------------

    test "build_auth_url targets TikTok with the scopes, redirect and state" do
      url    = @service.build_auth_url(redirect_uri: "https://example.com/admin/tiktok/callback", state: "abc123")
      params = URI.decode_www_form(URI(url).query).to_h

      assert url.start_with?(TikTok::AuthService::AUTH_URL)
      assert_equal "user.info.basic,video.publish", params["scope"]
      assert_equal "code",   params["response_type"]
      assert_equal "abc123", params["state"]
      assert_equal "https://example.com/admin/tiktok/callback", params["redirect_uri"]
    end

    test "build_auth_url generates a state when none is supplied" do
      url    = @service.build_auth_url(redirect_uri: "https://example.com/cb")
      params = URI.decode_www_form(URI(url).query).to_h

      assert params["state"].present?
    end

    # -------------------------------------------------------------------------
    # #exchange_code
    # -------------------------------------------------------------------------

    test "exchange_code persists the tokens and open_id on the user" do
      freeze_time do
        with_creator_info do
          with_token_response(token_payload) do
            @service.exchange_code("auth_code_123", redirect_uri: "https://example.com/cb")
          end
        end

        @user.reload
        assert_equal "act.new_token",   @user.tiktok_access_token
        assert_equal "rft.new_refresh", @user.tiktok_refresh_token
        assert_equal "open_id_abc",     @user.tiktok_open_id
        assert_equal "user.info.basic,video.publish", @user.tiktok_scope
        assert_equal 86_400.seconds.from_now,     @user.tiktok_token_expires_at
        assert_equal 31_536_000.seconds.from_now, @user.tiktok_refresh_expires_at
        assert @user.tiktok_connected?
      end
    end

    test "exchange_code stores the creator username for the admin UI" do
      with_creator_info(username: "thebandhandle") do
        with_token_response(token_payload) do
          @service.exchange_code("auth_code_123", redirect_uri: "https://example.com/cb")
        end
      end

      assert_equal "thebandhandle", @user.reload.tiktok_username
    end

    test "exchange_code still connects when the creator info lookup fails" do
      failing = Object.new
      failing.define_singleton_method(:query) { raise TikTok::ApiError, "creator info down" }

      TikTok::CreatorInfoService.stub(:new, failing) do
        with_token_response(token_payload) do
          assert_nothing_raised { @service.exchange_code("code", redirect_uri: "https://example.com/cb") }
        end
      end

      assert @user.reload.tiktok_connected?
    end

    test "exchange_code raises TokenExpiredError when TikTok rejects the code" do
      body = { "error" => "invalid_grant", "error_description" => "Authorization code is invalid", "log_id" => "log_9" }

      with_token_response(body, status: 400) do
        error = assert_raises(TikTok::TokenExpiredError) do
          @service.exchange_code("bad_code", redirect_uri: "https://example.com/cb")
        end
        assert_equal "invalid_grant", error.code
        assert_match(/Authorization code is invalid/, error.message)
      end

      assert_not @user.reload.tiktok_connected?
    end

    test "exchange_code raises when the response carries no access token" do
      with_token_response({ "open_id" => "abc" }) do
        assert_raises(TikTok::TokenExpiredError) do
          @service.exchange_code("code", redirect_uri: "https://example.com/cb")
        end
      end
    end

    # -------------------------------------------------------------------------
    # #refresh_access_token!
    # -------------------------------------------------------------------------

    test "refresh_access_token! swaps in the new access token" do
      user    = users(:one)
      service = TikTok::AuthService.new(user)
      original_expiry = user.tiktok_token_expires_at

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post(TikTok::AuthService::TOKEN_URL) do
          [ 200, { "Content-Type" => "application/json" },
            token_payload("access_token" => "act.refreshed", "refresh_token" => "rft.rotated").to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json, content_type: /\bjson$/; f.adapter :test, stubs }

      service.stub(:token_connection, conn) { service.refresh_access_token! }

      user.reload
      assert_equal "act.refreshed", user.tiktok_access_token
      assert_equal "rft.rotated",   user.tiktok_refresh_token
      assert user.tiktok_token_expires_at > original_expiry
    end

    test "refresh_access_token! keeps the existing refresh token when TikTok does not rotate it" do
      user    = users(:one)
      service = TikTok::AuthService.new(user)
      existing_refresh = user.tiktok_refresh_token

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post(TikTok::AuthService::TOKEN_URL) do
          [ 200, { "Content-Type" => "application/json" },
            { "access_token" => "act.refreshed", "expires_in" => 86_400 }.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json, content_type: /\bjson$/; f.adapter :test, stubs }

      service.stub(:token_connection, conn) { service.refresh_access_token! }

      assert_equal existing_refresh, user.reload.tiktok_refresh_token
    end

    test "refresh_access_token! raises TokenExpiredError when there is no refresh token" do
      assert_raises(TikTok::TokenExpiredError) { @service.refresh_access_token! }
    end

    # -------------------------------------------------------------------------
    # #disconnect
    # -------------------------------------------------------------------------

    test "disconnect clears every stored TikTok credential" do
      user    = users(:one)
      service = TikTok::AuthService.new(user)

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post(TikTok::AuthService::REVOKE_URL) { [ 200, { "Content-Type" => "application/json" }, "{}" ] }
      end
      conn = Faraday.new { |f| f.response :json, content_type: /\bjson$/; f.adapter :test, stubs }

      service.stub(:token_connection, conn) { service.disconnect }

      user.reload
      assert_nil user.tiktok_access_token
      assert_nil user.tiktok_refresh_token
      assert_nil user.tiktok_open_id
      assert_nil user.tiktok_username
      assert_nil user.tiktok_token_expires_at
      assert_not user.tiktok_connected?
    end

    test "disconnect clears credentials even when revocation fails" do
      user    = users(:one)
      service = TikTok::AuthService.new(user)

      failing = Object.new
      failing.define_singleton_method(:post) { |*_, &_blk| raise Faraday::ConnectionFailed, "network down" }

      service.stub(:token_connection, failing) { service.disconnect }

      assert_not user.reload.tiktok_connected?
    end
  end
end
