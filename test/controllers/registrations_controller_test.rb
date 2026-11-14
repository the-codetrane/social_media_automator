require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders registration form" do
    get new_registration_path
    assert_response :success
    assert_select "h1", "Create your account"
    assert_select "form[action=?]", registration_path
  end

  test "new shows link to sign in" do
    get new_registration_path
    assert_select "a[href=?]", new_session_path, text: "Sign in"
  end

  test "create with valid params creates user and signs in" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_redirected_to users_path
    assert cookies[:session_id].present?
    follow_redirect!
    assert_select "div", /Welcome! Your account has been created./
  end

  test "create with invalid params renders form with errors" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          name: "",
          email_address: "invalid",
          password: "short",
          password_confirmation: "mismatch"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]"
  end

  test "create with duplicate email renders form with errors" do
    existing_user = users(:one)

    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          name: "Duplicate User",
          email_address: existing_user.email_address,
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]"
  end

  test "create with mismatched passwords renders form with errors" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          name: "Test User",
          email_address: "testuser@example.com",
          password: "password123",
          password_confirmation: "differentpassword"
        }
      }
    end

    assert_response :unprocessable_entity
  end
end
