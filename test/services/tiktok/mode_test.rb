# frozen_string_literal: true

require "test_helper"

module TikTok
  # Covers sandbox/production mode resolution and the credential layouts it
  # accepts.  TikTok's sandbox is a separate app with its own key pair, so the
  # only thing that changes between modes is which pair we send.
  class ModeTest < ActiveSupport::TestCase
    def teardown
      AppSetting.find_by(key: TikTok::MODE_SETTING)&.destroy
      ENV.delete("TIKTOK_MODE")
    end

    # Swap in a credentials hash for the duration of the block.
    def with_credentials(tiktok_hash, &block)
      creds = Rails.application.credentials
      creds.stub(:tiktok, tiktok_hash) do
        creds.stub(:dig, ->(*keys) {
          keys.first == :tiktok ? tiktok_hash.dig(*keys[1..]) : nil
        }, &block)
      end
    end

    # -------------------------------------------------------------------------
    # Mode resolution
    # -------------------------------------------------------------------------

    test "defaults to production" do
      assert_equal "production", TikTok.mode
      assert_not TikTok.sandbox?
    end

    test "the AppSetting wins over everything else" do
      ENV["TIKTOK_MODE"] = "production"
      TikTok.mode = "sandbox"

      assert_equal "sandbox", TikTok.mode
      assert TikTok.sandbox?
    end

    test "falls back to TIKTOK_MODE when no AppSetting is stored" do
      ENV["TIKTOK_MODE"] = "sandbox"
      assert_equal "sandbox", TikTok.mode
    end

    test "an unrecognised stored mode falls back to production" do
      AppSetting.set(TikTok::MODE_SETTING, "staging")
      assert_equal "production", TikTok.mode
    end

    test "mode= rejects anything outside MODES" do
      assert_raises(ArgumentError) { TikTok.mode = "staging" }
      assert_equal "production", TikTok.mode
    end

    test "mode= round-trips both valid modes" do
      TikTok::MODES.each do |m|
        TikTok.mode = m
        assert_equal m, TikTok.mode
      end
    end

    # -------------------------------------------------------------------------
    # Credential layouts
    # -------------------------------------------------------------------------

    test "reads a nested per-mode credential layout" do
      creds = {
        production: { client_key: "aw_prod", client_secret: "prod_secret" },
        sandbox:    { client_key: "sbaw_sand", client_secret: "sand_secret" }
      }

      with_credentials(creds) do
        assert_equal "aw_prod",   TikTok.client_key(for_mode: "production")
        assert_equal "sbaw_sand", TikTok.client_key(for_mode: "sandbox")
        assert_equal "sand_secret", TikTok.client_secret(for_mode: "sandbox")
      end
    end

    test "reads a flat sandbox_-prefixed layout" do
      creds = {
        client_key: "aw_prod", client_secret: "prod_secret",
        sandbox_client_key: "sbaw_sand", sandbox_client_secret: "sand_secret"
      }

      with_credentials(creds) do
        assert_equal "aw_prod",   TikTok.client_key(for_mode: "production")
        assert_equal "sbaw_sand", TikTok.client_key(for_mode: "sandbox")
      end
    end

    test "treats a legacy flat pair as production so existing setups keep working" do
      with_credentials({ client_key: "aw_prod", client_secret: "prod_secret" }) do
        assert_equal "aw_prod", TikTok.client_key(for_mode: "production")
        assert TikTok.configured?(for_mode: "production")
        assert_not TikTok.configured?(for_mode: "sandbox")
      end
    end

    test "raises a ConfigurationError naming the missing key" do
      with_credentials({ client_key: "aw_prod", client_secret: "prod_secret" }) do
        error = assert_raises(TikTok::ConfigurationError) { TikTok.client_key(for_mode: "sandbox") }
        assert_match(/sandbox/, error.message)
        assert_match(/credentials:edit/, error.message)
      end
    end

    test "configured? requires both halves of the pair" do
      with_credentials({ sandbox: { client_key: "sbaw_sand" } }) do
        assert_not TikTok.configured?(for_mode: "sandbox")
      end
    end

    # -------------------------------------------------------------------------
    # AuthService picks up the mode
    # -------------------------------------------------------------------------

    test "AuthService builds the consent URL with the mode's client key" do
      creds = {
        production: { client_key: "aw_prod", client_secret: "s" },
        sandbox:    { client_key: "sbaw_sand", client_secret: "s" }
      }

      with_credentials(creds) do
        TikTok.mode = "sandbox"
        url = TikTok::AuthService.new(users(:two)).build_auth_url(redirect_uri: "https://example.com/cb")
        assert_equal "sbaw_sand", URI.decode_www_form(URI(url).query).to_h["client_key"]

        TikTok.mode = "production"
        url = TikTok::AuthService.new(users(:two)).build_auth_url(redirect_uri: "https://example.com/cb")
        assert_equal "aw_prod", URI.decode_www_form(URI(url).query).to_h["client_key"]
      end
    end

    test "an explicit mode overrides the active one" do
      creds = {
        production: { client_key: "aw_prod", client_secret: "s" },
        sandbox:    { client_key: "sbaw_sand", client_secret: "s" }
      }

      with_credentials(creds) do
        TikTok.mode = "production"
        url = TikTok::AuthService.new(users(:two), mode: "sandbox")
                                 .build_auth_url(redirect_uri: "https://example.com/cb")
        assert_equal "sbaw_sand", URI.decode_www_form(URI(url).query).to_h["client_key"]
      end
    end

    test "building the service does not raise when the other mode is unconfigured" do
      with_credentials({ client_key: "aw_prod", client_secret: "s" }) do
        assert_nothing_raised { TikTok::AuthService.new(users(:two), mode: "sandbox") }
      end
    end

    # -------------------------------------------------------------------------
    # Tokens do not cross environments
    # -------------------------------------------------------------------------

    test "the client refuses a token minted by the other environment" do
      user = users(:one)
      user.update!(tiktok_environment: "sandbox")
      TikTok.mode = "production"

      error = assert_raises(TikTok::TokenExpiredError) { TikTok::ApiClient.new(user).get("user/info/") }
      assert_match(/sandbox app/, error.message)
      assert_match(/production mode/, error.message)
    end

    test "the client accepts a token from the matching environment" do
      user = users(:one)
      user.update!(tiktok_environment: "sandbox")
      TikTok.mode = "sandbox"

      client = TikTok::ApiClient.new(user)
      conn = Faraday.new do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, Faraday::Adapter::Test::Stubs.new { |stub|
          stub.get("user/info/") { [ 200, { "Content-Type" => "application/json" }, { "data" => {} }.to_json ] }
        }
      end

      client.stub(:connection, conn) do
        assert_nothing_raised { client.get("user/info/") }
      end
    end

    test "a connection predating the toggle is left alone" do
      user = users(:one)
      assert_nil user.tiktok_environment
      TikTok.mode = "sandbox"

      client = TikTok::ApiClient.new(user)
      conn = Faraday.new do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, Faraday::Adapter::Test::Stubs.new { |stub|
          stub.get("user/info/") { [ 200, { "Content-Type" => "application/json" }, { "data" => {} }.to_json ] }
        }
      end

      client.stub(:connection, conn) do
        assert_nothing_raised { client.get("user/info/") }
      end
    end
  end
end
