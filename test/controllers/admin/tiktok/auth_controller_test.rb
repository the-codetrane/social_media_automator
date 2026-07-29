# frozen_string_literal: true

require "test_helper"

class Admin::TikTok::AuthControllerTest < ActionDispatch::IntegrationTest
  # ------------------------------------------------------------------
  # GET /admin/tiktok/connect
  # ------------------------------------------------------------------

  test "connect: returns 200 and renders the connect page" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path
    assert_response :ok
    assert_match "TikTok Connection", response.body
  end

  test "connect: assigns @auth_url pointing at the TikTok consent screen" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path
    assert_match %r{https://www\.tiktok\.com/v2/auth/authorize/},
                 @controller.view_assigns["auth_url"]
  end

  test "connect: @auth_url requests the video.publish scope and the admin callback" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path

    params = URI.decode_www_form(URI(@controller.view_assigns["auth_url"]).query).to_h
    assert_equal "user.info.basic,video.publish", params["scope"]
    assert_equal admin_tiktok_callback_url, params["redirect_uri"]
    assert params["state"].present?
  end

  test "connect: non-admin is redirected to root" do
    sign_in_as users(:one)
    get admin_tiktok_connect_path
    assert_redirected_to root_path
  end

  test "connect: unauthenticated request redirects to sign-in" do
    get admin_tiktok_connect_path
    assert_redirected_to new_session_path
  end

  # ------------------------------------------------------------------
  # POST /admin/tiktok/mode
  # ------------------------------------------------------------------

  test "connect: shows the active environment and both toggle buttons" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path

    assert_equal "production", @controller.view_assigns["mode"]
    TikTok::MODES.each do |m|
      assert_select "form[action=?] input[name=mode][value=?]", admin_tiktok_mode_path, m
    end
  end

  test "set_mode: switches to sandbox" do
    sign_in_as users(:admin)

    post admin_tiktok_mode_path, params: { mode: "sandbox" }

    assert_redirected_to admin_tiktok_connect_path
    assert_equal "sandbox", TikTok.mode
    assert_match(/sandbox/, flash[:notice])
  ensure
    AppSetting.find_by(key: TikTok::MODE_SETTING)&.destroy
  end

  test "set_mode: warns when the connected account belongs to the other app" do
    user = users(:admin)
    user.update!(tiktok_environment: "production")
    sign_in_as user

    post admin_tiktok_mode_path, params: { mode: "sandbox" }

    assert_match(/reconnect/i, flash[:notice])
  ensure
    AppSetting.find_by(key: TikTok::MODE_SETTING)&.destroy
  end

  test "set_mode: rejects an unknown mode" do
    sign_in_as users(:admin)

    post admin_tiktok_mode_path, params: { mode: "staging" }

    assert_redirected_to admin_tiktok_connect_path
    assert_match(/Could not change mode/, flash[:alert])
    assert_equal "production", TikTok.mode
  end

  test "set_mode: non-admin is redirected to root" do
    sign_in_as users(:one)
    post admin_tiktok_mode_path, params: { mode: "sandbox" }
    assert_redirected_to root_path
    assert_equal "production", TikTok.mode
  end

  # ------------------------------------------------------------------
  # GET /admin/tiktok/callback
  # ------------------------------------------------------------------

  test "callback: exchanges the code and redirects with a success notice" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path                                # seeds session state
    state = URI.decode_www_form(URI(@controller.view_assigns["auth_url"]).query).to_h["state"]

    exchanged = nil
    service = Object.new
    service.define_singleton_method(:exchange_code) { |code, redirect_uri:| exchanged = [ code, redirect_uri ] }

    TikTok::AuthService.stub(:new, service) do
      get admin_tiktok_callback_path(code: "auth_code_123", state: state)
    end

    assert_redirected_to admin_tiktok_connect_path
    assert_equal "TikTok connected successfully.", flash[:notice]
    assert_equal "auth_code_123", exchanged.first
  end

  test "callback: rejects a state that does not match the one issued" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path

    TikTok::AuthService.stub(:new, ->(_) { raise "should not exchange" }) do
      get admin_tiktok_callback_path(code: "auth_code_123", state: "forged")
    end

    assert_redirected_to admin_tiktok_connect_path
    assert_match(/state mismatch/, flash[:alert])
  end

  test "callback: redirects with an alert when TikTok returns no code" do
    sign_in_as users(:admin)
    get admin_tiktok_callback_path(error: "access_denied")

    assert_redirected_to admin_tiktok_connect_path
    assert_match(/No authorisation code/, flash[:alert])
  end

  test "callback: surfaces a TikTok error as an alert" do
    sign_in_as users(:admin)
    get admin_tiktok_connect_path
    state = URI.decode_www_form(URI(@controller.view_assigns["auth_url"]).query).to_h["state"]

    service = Object.new
    service.define_singleton_method(:exchange_code) { |_code, **| raise TikTok::TokenExpiredError, "code already used" }

    TikTok::AuthService.stub(:new, service) do
      get admin_tiktok_callback_path(code: "stale", state: state)
    end

    assert_redirected_to admin_tiktok_connect_path
    assert_match(/code already used/, flash[:alert])
  end

  test "callback: non-admin is redirected to root" do
    sign_in_as users(:one)
    get admin_tiktok_callback_path(code: "x")
    assert_redirected_to root_path
  end

  # ------------------------------------------------------------------
  # POST /admin/tiktok/refresh_token
  # ------------------------------------------------------------------

  test "refresh_token: refreshes and redirects with a notice" do
    sign_in_as users(:admin)

    refreshed = false
    service = Object.new
    service.define_singleton_method(:refresh_access_token!) { refreshed = true }

    TikTok::AuthService.stub(:new, service) do
      post admin_tiktok_refresh_token_path
    end

    assert refreshed
    assert_redirected_to admin_tiktok_connect_path
    assert_equal "TikTok access token refreshed.", flash[:notice]
  end

  test "refresh_token: surfaces a failure as an alert" do
    sign_in_as users(:admin)

    service = Object.new
    service.define_singleton_method(:refresh_access_token!) { raise TikTok::TokenExpiredError, "refresh token expired" }

    TikTok::AuthService.stub(:new, service) do
      post admin_tiktok_refresh_token_path
    end

    assert_match(/refresh token expired/, flash[:alert])
  end

  # ------------------------------------------------------------------
  # DELETE /admin/tiktok/disconnect
  # ------------------------------------------------------------------

  test "disconnect: clears the credentials and redirects" do
    user = users(:admin)
    sign_in_as user

    service = Object.new
    service.define_singleton_method(:disconnect) do
      user.update!(tiktok_access_token: nil, tiktok_open_id: nil)
    end

    TikTok::AuthService.stub(:new, service) do
      delete admin_tiktok_disconnect_path
    end

    assert_redirected_to admin_tiktok_connect_path
    assert_equal "TikTok disconnected.", flash[:notice]
    assert_not user.reload.tiktok_connected?
  end

  test "disconnect: non-admin is redirected to root" do
    sign_in_as users(:one)
    delete admin_tiktok_disconnect_path
    assert_redirected_to root_path
  end
end
