# frozen_string_literal: true

require "test_helper"

module Instagram
  class AuthServiceTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user    = users(:one)
      @service = Instagram::AuthService.new(@user)

      # Stub credentials so tests don't depend on encrypted credentials file
      @service.instance_variable_set(:@app_id,     "test_app_id_123")
      @service.instance_variable_set(:@app_secret, "test_app_secret_456")
    end

    # -------------------------------------------------------------------------
    # #token_expiring?
    # -------------------------------------------------------------------------

    test "token_expiring? returns false when token expires far in the future" do
      @user.instagram_token_expires_at = 30.days.from_now
      assert_not @service.token_expiring?
    end

    test "token_expiring? returns true when token expires within buffer window" do
      @user.instagram_token_expires_at = 3.days.from_now
      assert @service.token_expiring?  # default buffer is 7 days
    end

    test "token_expiring? returns true when token is already expired" do
      @user.instagram_token_expires_at = 1.day.ago
      assert @service.token_expiring?
    end

    test "token_expiring? returns true when expires_at is nil" do
      @user.instagram_token_expires_at = nil
      assert @service.token_expiring?
    end

    test "token_expiring? respects a custom buffer" do
      @user.instagram_token_expires_at = 10.days.from_now
      assert_not @service.token_expiring?(buffer: 5.days)
      assert     @service.token_expiring?(buffer: 15.days)
    end

    # -------------------------------------------------------------------------
    # #refresh_long_lived_token
    # -------------------------------------------------------------------------

    test "refresh_long_lived_token raises TokenExpiredError when no token stored" do
      @user.instagram_access_token = nil
      assert_raises(Instagram::TokenExpiredError) { @service.refresh_long_lived_token }
    end

    test "refresh_long_lived_token updates token and expiry on success" do
      new_token      = "EAAnew_refreshed_token"
      expires_in     = 5_184_000  # 60 days in seconds
      response_body  = { "access_token" => new_token, "token_type" => "bearer", "expires_in" => expires_in }

      # Stub the private graph_get call to avoid real HTTP
      @service.stub(:graph_get, ->(_url, _params) { response_body }) do
        freeze_time do
          @service.refresh_long_lived_token
          assert_equal new_token, @user.reload.instagram_access_token
          assert_in_delta (Time.current + expires_in.seconds).to_i,
                          @user.instagram_token_expires_at.to_i,
                          2
        end
      end
    end

    # -------------------------------------------------------------------------
    # #exchange_code_for_token
    # -------------------------------------------------------------------------

    test "exchange_code_for_token orchestrates short-lived → long-lived → account and persists to user" do
      short_token = "EAAshort"
      long_token  = "EAAlong_lived_token"
      expires_in  = 5_184_000
      ig_user_id  = "17841400099999"
      page_id     = "10158000000001"
      username    = "cainandco"

      call_count = 0
      graph_get_stub = lambda do |_url, _params|
        call_count += 1
        case call_count
        when 1 then { "access_token" => short_token }
        when 2 then { "access_token" => long_token, "expires_in" => expires_in }
        when 3
          { "data" => [ { "id" => page_id, "name" => "Cain & Co.",
                          "instagram_business_account" => { "id" => ig_user_id, "username" => username } } ] }
        end
      end

      @service.stub(:graph_get, graph_get_stub) do
        freeze_time do
          @service.exchange_code_for_token("auth_code_xyz", redirect_uri: "https://app.example.com/callback")

          updated = @user.reload
          assert_equal long_token,  updated.instagram_access_token
          assert_equal ig_user_id,  updated.instagram_user_id
          assert_equal page_id,     updated.instagram_page_id
          assert_equal username,    updated.instagram_username
          assert_in_delta (Time.current + expires_in.seconds).to_i,
                          updated.instagram_token_expires_at.to_i, 2
        end
      end
    end

    test "connect_with_token persists username alongside user_id and page_id" do
      long_token = "EAAlong"
      expires_in = 5_184_000
      ig_user_id = "17841400099999"
      page_id    = "10158000000001"
      username   = "cainandco"

      graph_get_stub = lambda do |_url, _params|
        { "data" => [ { "id" => page_id, "name" => "Cain & Co.",
                        "instagram_business_account" => { "id" => ig_user_id, "username" => username } } ] }
      end

      @service.stub(:graph_get, graph_get_stub) do
        freeze_time do
          @service.connect_with_token(long_token, expires_in: expires_in, ig_user_id: ig_user_id)

          updated = @user.reload
          assert_equal ig_user_id, updated.instagram_user_id
          assert_equal page_id,    updated.instagram_page_id
          assert_equal username,   updated.instagram_username
        end
      end
    end

    test "exchange_code_for_token raises ApiError when no Instagram Business Account found" do
      graph_get_stub = lambda do |_url, _params|
        { "data" => [ { "id" => "page_1", "name" => "My Page" } ] }  # no instagram_business_account
      end

      # We need all three internal calls to return something; override fetch_ig_user_id only
      @service.stub(:fetch_short_lived_token, "EAAshort") do
        @service.stub(:fetch_long_lived_token, { token: "EAAlong", expires_in: 5_000_000 }) do
          @service.stub(:graph_get, graph_get_stub) do
            assert_raises(Instagram::ApiError) do
              @service.exchange_code_for_token("code", redirect_uri: "https://example.com/cb")
            end
          end
        end
      end
    end
  end
end
