# frozen_string_literal: true

require "test_helper"

class Admin::Instagram::AuthControllerTest < ActionDispatch::IntegrationTest
  # ------------------------------------------------------------------
  # GET /admin/instagram/connect
  # ------------------------------------------------------------------

  test "connect: returns 200 and renders the connect page" do
    sign_in_as users(:admin)
    get admin_instagram_connect_path
    assert_response :ok
    assert_match "Instagram Connection", response.body
  end

  test "connect: assigns @auth_url containing the Meta OAuth endpoint" do
    sign_in_as users(:admin)
    get admin_instagram_connect_path
    assert_match %r{https://www\.facebook\.com/v25\.0/dialog/oauth},
                 @controller.view_assigns["auth_url"]
  end

  test "connect: @auth_url contains the admin callback redirect_uri" do
    sign_in_as users(:admin)
    get admin_instagram_connect_path
    decoded = URI.decode_www_form_component(@controller.view_assigns["auth_url"])
    assert_includes decoded, admin_instagram_callback_url
  end

  test "connect: @auth_url includes required OAuth scopes" do
    sign_in_as users(:admin)
    get admin_instagram_connect_path
    auth_url = @controller.view_assigns["auth_url"]
    assert_match "instagram_basic",           auth_url
    assert_match "instagram_manage_comments", auth_url
    assert_match "pages_show_list",           auth_url
  end

  test "connect: non-admin is redirected to root" do
    sign_in_as users(:one)
    get admin_instagram_connect_path
    assert_redirected_to root_path
  end

  test "connect: unauthenticated request redirects to sign-in" do
    get admin_instagram_connect_path
    assert_redirected_to new_session_path
  end

  # ------------------------------------------------------------------
  # GET /admin/instagram/callback
  # ------------------------------------------------------------------

  test "callback: renders account selection view with accounts from AuthService" do
    user     = users(:admin)
    accounts = [
      { ig_user_id: "111", page_id: "p1", page_name: "Cain & Co.", username: "cainandco", profile_picture_url: nil },
      { ig_user_id: "222", page_id: "p2", page_name: "Other Page", username: "other",     profile_picture_url: nil }
    ]
    service = Minitest::Mock.new
    service.expect(:exchange_code_for_long_lived_token, { token: "LONG_TOKEN", expires_in: 5_184_000 }) do |code, redirect_uri:|
      code == "valid_code" && redirect_uri == admin_instagram_callback_url
    end
    service.expect(:list_ig_accounts, accounts, [ "LONG_TOKEN" ])

    sign_in_as user
    Instagram::AuthService.stub(:new, service) do
      get admin_instagram_callback_path, params: { code: "valid_code" }
    end

    assert_response :ok
    assert_match "Cain &amp; Co.", response.body
    assert_match "@cainandco",     response.body
    service.verify
  end

  test "callback: stores pending token in session for select_account step" do
    user    = users(:admin)
    service = Minitest::Mock.new
    service.expect(:exchange_code_for_long_lived_token, { token: "PENDING_TOKEN", expires_in: 100 }) { true }
    service.expect(:list_ig_accounts, [], [ "PENDING_TOKEN" ])

    sign_in_as user
    Instagram::AuthService.stub(:new, service) do
      get admin_instagram_callback_path, params: { code: "any_code" }
    end

    assert_equal "PENDING_TOKEN", session[:ig_pending_token]
  end

  test "callback: redirects to connect with an alert when code param is absent" do
    sign_in_as users(:admin)
    get admin_instagram_callback_path   # no ?code=

    assert_redirected_to admin_instagram_connect_path
    assert_match "No authorisation code was returned by Instagram.", flash[:alert]
  end

  test "callback: redirects to connect with an alert when AuthService raises ApiError" do
    user    = users(:admin)
    service = Minitest::Mock.new
    service.expect(:exchange_code_for_long_lived_token, nil) { raise Instagram::ApiError.new("Invalid OAuth code.") }

    sign_in_as user
    Instagram::AuthService.stub(:new, service) do
      get admin_instagram_callback_path, params: { code: "bad_code" }
    end

    assert_redirected_to admin_instagram_connect_path
    assert_match "Instagram connection failed: Invalid OAuth code.", flash[:alert]
  end

  test "callback: unauthenticated request redirects to sign-in" do
    get admin_instagram_callback_path, params: { code: "some_code" }
    assert_redirected_to new_session_path
  end

  # ------------------------------------------------------------------
  # GET /admin/instagram/connect — username display
  # ------------------------------------------------------------------

  test "connect: shows connected username when instagram_username is present" do
    sign_in_as users(:admin)
    get admin_instagram_connect_path
    assert_match "@cainandco", response.body
  end
end
