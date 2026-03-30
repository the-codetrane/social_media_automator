require "test_helper"

class ConnectedDrivesControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "index redirects when not signed in" do
    get connected_drives_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get connected_drives_path
    assert_response :success
  end

  test "index lists all drives" do
    sign_in_as(@user)
    get connected_drives_path
    assert_match "My Content Drive", response.body
    assert_match "Archive Drive", response.body
  end

  test "index shows provider badge" do
    sign_in_as(@user)
    get connected_drives_path
    assert_match "Google drive", response.body
  end

  test "index shows sync metadata" do
    sign_in_as(@user)
    get connected_drives_path
    assert_match "60", response.body
    assert_match "folder_abc123", response.body
  end
end
