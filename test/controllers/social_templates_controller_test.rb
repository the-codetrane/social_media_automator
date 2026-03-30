require "test_helper"

class SocialTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "index redirects when not signed in" do
    get social_templates_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get social_templates_path
    assert_response :success
  end

  test "index lists all templates" do
    sign_in_as(@user)
    get social_templates_path
    assert_match "Instagram Reels Default", response.body
    assert_match "YouTube Shorts Default", response.body
  end

  test "index shows platform badges" do
    sign_in_as(@user)
    get social_templates_path
    assert_match "instagram", response.body
    assert_match "youtube", response.body
  end

  test "index shows global badge for templates without an owner" do
    sign_in_as(@user)
    get social_templates_path
    assert_match "Global Template", response.body
  end

  test "index shows owner name for user-scoped templates" do
    sign_in_as(@user)
    get social_templates_path
    assert_match "Test User1", response.body
  end

  test "index shows default captions" do
    sign_in_as(@user)
    get social_templates_path
    assert_match "Check this out!", response.body
    assert_match "Watch till the end!", response.body
  end
end
