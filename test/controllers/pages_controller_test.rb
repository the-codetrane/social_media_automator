# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  # The whole point of these pages is that Meta, Google and TikTok reviewers can
  # fetch them without an account, so the unauthenticated cases are the ones
  # that actually matter.

  test "home: is reachable without signing in and is not a sign-in page" do
    get root_path
    assert_response :ok
    assert_select "h1", "Plan once. Publish everywhere."
    assert_select "form[action=?]", session_path, count: 0
  end

  test "home: links to both legal pages in the page body, not just the footer" do
    get root_path
    assert_select "main a[href=?]", tos_path
    assert_select "main a[href=?]", privacy_path
  end

  test "home: shows the same logo the developer portals use as the app icon" do
    get root_path
    assert_select "img[src=?]", "/icon.png"
    assert_select "link[rel=icon][href=?]", "/icon.png"
  end

  test "home: sends signed-in users on to the dashboard" do
    sign_in_as users(:one)
    get root_path
    assert_redirected_to users_path
  end

  test "tos: is reachable without signing in" do
    get tos_path
    assert_response :ok
    assert_select "h1", "Terms of Service"
  end

  test "privacy: is reachable without signing in" do
    get privacy_path
    assert_response :ok
    assert_select "h1", "Privacy Policy"
  end

  test "tos: does not redirect to the sign-in page" do
    get tos_path
    assert_response :ok
    assert_not_equal new_session_url, response.location
  end

  test "privacy: does not redirect to the sign-in page" do
    get privacy_path
    assert_response :ok
    assert_not_equal new_session_url, response.location
  end

  test "tos: renders without the authenticated nav" do
    get tos_path
    assert_select "nav", count: 0
  end

  test "legal pages are still reachable when signed in" do
    sign_in_as users(:one)

    get tos_path
    assert_response :ok

    get privacy_path
    assert_response :ok
  end

  test "tos: names every platform the service publishes to" do
    get tos_path
    %w[Instagram Facebook YouTube TikTok].each do |platform|
      assert_match platform, response.body, "expected the Terms to mention #{platform}"
    end
  end

  test "privacy: discloses the data categories the app actually stores" do
    get privacy_path
    # \s+ rather than a literal space: the ERB source wraps these phrases across lines.
    [ /access and refresh\s+tokens/i, /GPS\s+coordinates/i, /IP\s+address/i, /hashed/i ].each do |pattern|
      assert_match pattern, response.body
    end
  end

  test "legal pages cross-link to each other" do
    get tos_path
    assert_select "a[href=?]", privacy_path

    get privacy_path
    assert_select "a[href=?]", tos_path
  end

  test "the footer links to both legal pages from an ordinary page" do
    sign_in_as users(:one)
    get planned_posts_path

    assert_select "footer a[href=?]", tos_path
    assert_select "footer a[href=?]", privacy_path
  end

  test "both pages show the same last-updated date" do
    expected = PagesController::LAST_UPDATED.strftime("%B %-d, %Y")

    get tos_path
    assert_match expected, response.body

    get privacy_path
    assert_match expected, response.body
  end
end
