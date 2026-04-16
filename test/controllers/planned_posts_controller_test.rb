require "test_helper"

class PlannedPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @planned_post = planned_posts(:draft_post)
    @media_asset = media_assets(:sample_image)
    @social_template = social_templates(:instagram_default)
  end

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

  # Show action tests
  test "show redirects when not signed in" do
    get planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_response :success
  end

  test "show displays post details" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_match @planned_post.caption, response.body
    assert_match @planned_post.platform, response.body
  end

  test "show has edit link" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", edit_planned_post_path(@planned_post)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", planned_posts_path
  end

  test "show displays hashtags" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_match @planned_post.hashtags, response.body
  end

  test "show links to media asset" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "a[href=?]", media_asset_path(@planned_post.media_asset)
  end

  test "show displays image media preview" do
    sign_in_as(@user)
    get planned_post_path(@planned_post)
    assert_select "img[src=?]", @planned_post.media_asset.public_url
  end

  test "show displays video media preview" do
    sign_in_as(@user)
    video_post = planned_posts(:scheduled_post)
    get planned_post_path(video_post)
    assert_select "video" do
      assert_select "source[src=?]", video_post.media_asset.public_url
    end
  end

  test "show does not display media preview when no public url" do
    sign_in_as(@user)
    # Create a post with media asset that has no public URL
    post_no_url = PlannedPost.create!(
      user: @user,
      media_asset: media_assets(:sample_image_no_url),
      platform: :instagram,
      status: :draft,
      caption: "Test post"
    )
    get planned_post_path(post_no_url)
    assert_response :success
    assert_select "img", count: 0
    assert_select "video", count: 0
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_planned_post_path(@planned_post)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "textarea[name='planned_post[caption]']", text: /Beautiful sunset/
    assert_select "input[name='planned_post[hashtags]'][value=?]", @planned_post.hashtags
    assert_select "select[name='planned_post[status]']"
  end

  test "edit shows media asset select" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "select[name='planned_post[media_asset_id]']"
  end

  test "edit shows social template select" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    assert_select "select[name='planned_post[social_template_id]']"
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "New Caption" } }
    assert_redirected_to new_session_path
  end

  test "update changes post attributes" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "Updated Caption" } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "Updated Caption", @planned_post.caption
  end

  test "update can change hashtags" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { hashtags: "#newtag #updated" } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "#newtag #updated", @planned_post.hashtags
  end

  test "update can change status" do
    sign_in_as(@user)
    scheduled_time = 3.days.from_now
    patch planned_post_path(@planned_post), params: { planned_post: { status: "scheduled", scheduled_at: scheduled_time } }
    assert_redirected_to planned_post_path(@planned_post)
    @planned_post.reload
    assert_equal "scheduled", @planned_post.status
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch planned_post_path(@planned_post), params: { planned_post: { caption: "New" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end

  # URL decoding tests
  test "index decodes URL-encoded media asset names" do
    sign_in_as(@user)
    get planned_posts_path
    # Should show decoded name, not URL-encoded
    assert_match "Big Guys BBQ", response.body
  end

  test "show decodes URL-encoded media asset name in link" do
    sign_in_as(@user)
    url_encoded_post = planned_posts(:url_encoded_asset_post)
    get planned_post_path(url_encoded_post)
    # The media asset link text should be decoded
    assert_match "Big Guys BBQ", response.body
    assert_select "a[href=?]", media_asset_path(url_encoded_post.media_asset), text: /Big Guys BBQ/
  end

  test "edit decodes URL-encoded media asset names in dropdown" do
    sign_in_as(@user)
    get edit_planned_post_path(@planned_post)
    # The select dropdown should show decoded names
    assert_match "Big Guys BBQ", response.body
  end
end
