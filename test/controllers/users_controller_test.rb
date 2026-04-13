require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_user = users(:two)
  end

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

  # Show action tests
  test "show redirects when not signed in" do
    get user_path(@user)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get user_path(@user)
    assert_response :success
  end

  test "show displays user details" do
    sign_in_as(@user)
    get user_path(@user)
    assert_match @user.name, response.body
    assert_match @user.email_address, response.body
  end

  test "show has edit link" do
    sign_in_as(@user)
    get user_path(@user)
    assert_select "a[href=?]", edit_user_path(@user)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get user_path(@user)
    assert_select "a[href=?]", users_path
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_user_path(@user)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_user_path(@user)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_user_path(@user)
    assert_select "input[name='user[name]'][value=?]", @user.name
    assert_select "input[name='user[email_address]'][value=?]", @user.email_address
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch user_path(@user), params: { user: { name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "update changes user attributes" do
    sign_in_as(@user)
    patch user_path(@user), params: { user: { name: "Updated Name" } }
    assert_redirected_to user_path(@user)
    @user.reload
    assert_equal "Updated Name", @user.name
  end

  test "update with invalid data renders edit" do
    sign_in_as(@user)
    patch user_path(@user), params: { user: { email_address: "" } }
    assert_response :unprocessable_entity
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch user_path(@user), params: { user: { name: "New Name" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end
end
