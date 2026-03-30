require "test_helper"

class MediaAssetsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "index redirects when not signed in" do
    get media_assets_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get media_assets_path
    assert_response :success
  end

  test "index lists all assets" do
    sign_in_as(@user)
    get media_assets_path
    assert_match "sunset.jpg", response.body
    assert_match "reel.mp4", response.body
  end

  test "index shows media type badges" do
    sign_in_as(@user)
    get media_assets_path
    assert_match "image", response.body
    assert_match "video", response.body
  end

  test "index shows status badges" do
    sign_in_as(@user)
    get media_assets_path
    assert_match "processed", response.body
  end

  test "index shows file size" do
    sign_in_as(@user)
    get media_assets_path
    assert_match "1.95 MB", response.body
  end

  test "index shows video duration" do
    sign_in_as(@user)
    get media_assets_path
    assert_match "31s", response.body
  end
end
