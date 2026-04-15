# frozen_string_literal: true

require "test_helper"

class Instagram::AuthControllerTest < ActionDispatch::IntegrationTest
  # sign_in_as is provided by SessionTestHelper
  # (test/test_helpers/session_test_helper.rb), included into all integration tests.

  # ------------------------------------------------------------------
  # GET /instagram/connect
  # ------------------------------------------------------------------

  test "connect: returns 200 and renders the connect page" do
    sign_in_as users(:one)
    get instagram_connect_path
    assert_response :ok
    assert_match "Connect Instagram", response.body
  end

  test "connect: assigns @auth_url containing the Meta OAuth endpoint" do
    sign_in_as users(:one)
    get instagram_connect_path
    assert_match %r{https://www\.facebook\.com/v25\.0/dialog/oauth},
                 @controller.view_assigns["auth_url"]
  end

  test "connect: @auth_url contains the callback redirect_uri" do
    sign_in_as users(:one)
    get instagram_connect_path
    decoded = URI.decode_www_form_component(@controller.view_assigns["auth_url"])
    assert_includes decoded, instagram_callback_url
  end

  test "connect: @auth_url includes required OAuth scopes" do
    sign_in_as users(:one)
    get instagram_connect_path
    auth_url = @controller.view_assigns["auth_url"]
    assert_match "instagram_basic",          auth_url
    assert_match "instagram_manage_comments", auth_url
    assert_match "pages_show_list",           auth_url
  end

  test "connect: unauthenticated request redirects to sign-in" do
    get instagram_connect_path
    assert_redirected_to new_session_path
  end

  # ------------------------------------------------------------------
  # GET /instagram/callback
  # ------------------------------------------------------------------

  test "callback: exchanges the code and redirects to root on success" do
    user    = users(:one)
    service = Minitest::Mock.new
    service.expect(:exchange_code_for_token, user) do |code, redirect_uri:|
      code == "valid_code" && redirect_uri == instagram_callback_url
    end

    sign_in_as user
    Instagram::AuthService.stub(:new, service) do
      get instagram_callback_path, params: { code: "valid_code" }
    end

    assert_redirected_to "/"
    assert_equal "Instagram account connected successfully.", flash[:notice]
    service.verify
  end

  test "callback: redirects to connect with an alert when code param is absent" do
    sign_in_as users(:one)
    get instagram_callback_path   # no ?code=

    assert_redirected_to instagram_connect_path
    assert_match "No authorisation code was returned by Instagram.", flash[:alert]
  end

  test "callback: redirects to connect with an alert when AuthService raises ApiError" do
    user    = users(:one)
    service = Minitest::Mock.new
    service.expect(:exchange_code_for_token, nil) { raise Instagram::ApiError.new("Invalid OAuth code.") }

    sign_in_as user
    Instagram::AuthService.stub(:new, service) do
      get instagram_callback_path, params: { code: "bad_code" }
    end

    assert_redirected_to instagram_connect_path
    assert_match "Instagram connection failed: Invalid OAuth code.", flash[:alert]
  end

  test "callback: unauthenticated request redirects to sign-in" do
    get instagram_callback_path, params: { code: "some_code" }
    assert_redirected_to new_session_path
  end
end
