require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "index redirects when not signed in" do
    get users_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get users_path
    assert_response :success
  end

  test "index lists all users" do
    sign_in_as(@user)
    get users_path
    assert_select "p", text: /Test User1/
    assert_select "p", text: /Test User2/
  end

  test "index shows email addresses" do
    sign_in_as(@user)
    get users_path
    assert_match "user1@example.com", response.body
    assert_match "user2@example.com", response.body
  end

  test "index shows instagram connected badge" do
    sign_in_as(@user)
    get users_path
    assert_match "Instagram Connected", response.body
  end
end
