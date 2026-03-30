require "test_helper"

class PlannedPostsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "index redirects when not signed in" do
    get planned_posts_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get planned_posts_path
    assert_response :success
  end

  test "index lists all posts" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "Beautiful sunset", response.body
    assert_match "Amazing reel", response.body
    assert_match "Live on IG", response.body
  end

  test "index shows platform badges" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "instagram", response.body
    assert_match "youtube", response.body
  end

  test "index shows status badges" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "draft", response.body
    assert_match "scheduled", response.body
    assert_match "published", response.body
  end

  test "index shows hashtags" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "#nature #sunset #photography", response.body
  end

  test "index shows external post id for published post" do
    sign_in_as(@user)
    get planned_posts_path
    assert_match "ig_post_abc", response.body
  end
end
