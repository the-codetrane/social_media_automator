require "test_helper"

class SocialTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @social_template = social_templates(:instagram_default)
    @user_template = social_templates(:youtube_shorts)
  end

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

  # Show action tests
  test "show redirects when not signed in" do
    get social_template_path(@social_template)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_response :success
  end

  test "show displays template details" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_match @social_template.name, response.body
    assert_match @social_template.platform, response.body
  end

  test "show has edit link" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_select "a[href=?]", edit_social_template_path(@social_template)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_select "a[href=?]", social_templates_path
  end

  test "show displays default caption" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_match @social_template.default_caption, response.body
  end

  test "show displays max caption length" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_match "#{@social_template.max_caption_length}", response.body
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_social_template_path(@social_template)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_social_template_path(@social_template)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_social_template_path(@social_template)
    assert_select "input[name='social_template[name]'][value=?]", @social_template.name
    assert_select "select[name='social_template[platform]']"
    assert_select "textarea[name='social_template[default_caption]']", text: /Check this out/
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch social_template_path(@social_template), params: { social_template: { name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "update changes template attributes" do
    sign_in_as(@user)
    patch social_template_path(@social_template), params: { social_template: { name: "Updated Template" } }
    assert_redirected_to social_template_path(@social_template)
    @social_template.reload
    assert_equal "Updated Template", @social_template.name
  end

  test "update can change default caption" do
    sign_in_as(@user)
    patch social_template_path(@social_template), params: { social_template: { default_caption: "New default caption" } }
    assert_redirected_to social_template_path(@social_template)
    @social_template.reload
    assert_equal "New default caption", @social_template.default_caption
  end

  test "update can change max caption length" do
    sign_in_as(@user)
    patch social_template_path(@social_template), params: { social_template: { max_caption_length: 3000 } }
    assert_redirected_to social_template_path(@social_template)
    @social_template.reload
    assert_equal 3000, @social_template.max_caption_length
  end

  test "update with invalid data renders edit" do
    sign_in_as(@user)
    patch social_template_path(@social_template), params: { social_template: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch social_template_path(@social_template), params: { social_template: { name: "New Name" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end
end
