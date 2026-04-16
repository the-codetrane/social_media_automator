require "test_helper"

class MediaAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @media_asset = media_assets(:sample_image)
  end

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

  test "index displays image thumbnail preview" do
    sign_in_as(@user)
    get media_assets_path
    assert_select "img[src=?]", @media_asset.public_url
  end

  test "index displays video thumbnail preview" do
    sign_in_as(@user)
    get media_assets_path
    video_asset = media_assets(:sample_video)
    assert_select "video source[src=?]", video_asset.public_url
  end

  test "index displays placeholder when no public url" do
    sign_in_as(@user)
    get media_assets_path
    # Should have placeholder SVG for assets without public URL
    assert_select "svg"
  end

  # Show action tests
  test "show redirects when not signed in" do
    get media_asset_path(@media_asset)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_response :success
  end

  test "show displays asset details" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_match @media_asset.external_name, response.body
    assert_match @media_asset.media_type, response.body
  end

  test "show has edit link" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "a[href=?]", edit_media_asset_path(@media_asset)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "a[href=?]", media_assets_path
  end

  test "show displays dimensions" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_match "#{@media_asset.width}", response.body
    assert_match "#{@media_asset.height}", response.body
  end

  test "show displays image media preview" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "img[src=?]", @media_asset.public_url
  end

  test "show displays video media preview" do
    sign_in_as(@user)
    video_asset = media_assets(:sample_video)
    get media_asset_path(video_asset)
    assert_select "video" do
      assert_select "source[src=?]", video_asset.public_url
    end
  end

  test "show does not display media preview when no public url" do
    sign_in_as(@user)
    asset_no_url = media_assets(:sample_image_no_url)
    get media_asset_path(asset_no_url)
    assert_response :success
    assert_select "img", count: 0
    assert_select "video", count: 0
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_media_asset_path(@media_asset)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_media_asset_path(@media_asset)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_media_asset_path(@media_asset)
    assert_select "input[name='media_asset[external_name]'][value=?]", @media_asset.external_name
    assert_select "select[name='media_asset[status]']"
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "update changes asset attributes" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "updated_image.jpg" } }
    assert_redirected_to media_asset_path(@media_asset)
    @media_asset.reload
    assert_equal "updated_image.jpg", @media_asset.external_name
  end

  test "update can change status" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { status: "archived" } }
    assert_redirected_to media_asset_path(@media_asset)
    @media_asset.reload
    assert_equal "archived", @media_asset.status
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "new.jpg" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end

  # URL decoding tests
  test "index decodes URL-encoded names" do
    sign_in_as(@user)
    get media_assets_path
    # Should show decoded name, not URL-encoded
    assert_match "Big Guys BBQ", response.body
    assert_no_match(/%20/, response.body.scan(/Big.*BBQ/).first || "")
  end

  test "show decodes URL-encoded name in heading" do
    sign_in_as(@user)
    url_encoded_asset = media_assets(:url_encoded_name)
    get media_asset_path(url_encoded_asset)
    assert_match "Big Guys BBQ", response.body
    # The h1 should contain decoded name
    assert_select "h1", text: /Big Guys BBQ/
  end

  test "show decodes URL-encoded name in title" do
    sign_in_as(@user)
    url_encoded_asset = media_assets(:url_encoded_name)
    get media_asset_path(url_encoded_asset)
    assert_select "title", text: /Big Guys BBQ/
  end
end
