require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "index redirects when not signed in" do
    get sessions_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get sessions_path
    assert_response :success
  end

  test "index lists sessions with ip and user agent" do
    sign_in_as(@user)
    get sessions_path
    assert_match "127.0.0.1", response.body
    assert_match "Rails Testing", response.body
  end

  test "index highlights the current session" do
    sign_in_as(@user)
    get sessions_path
    assert_match "Current", response.body
  end
end
