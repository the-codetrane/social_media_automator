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

  # New action tests
  test "new redirects when not signed in" do
    get new_social_template_path
    assert_redirected_to new_session_path
  end

  test "new returns success when signed in" do
    sign_in_as(@user)
    get new_social_template_path
    assert_response :success
  end

  test "new displays blank form" do
    sign_in_as(@user)
    get new_social_template_path
    assert_select "input[name='social_template[name]']"
    assert_select "select[name='social_template[platform]']"
    assert_select "textarea[name='social_template[default_caption]']"
  end

  test "new has cancel link to index" do
    sign_in_as(@user)
    get new_social_template_path
    assert_select "a[href=?]", social_templates_path
  end

  # Create action tests
  test "create redirects when not signed in" do
    post social_templates_path, params: { social_template: { name: "Test", platform: "instagram" } }
    assert_redirected_to new_session_path
  end

  test "create saves template and redirects to show" do
    sign_in_as(@user)
    assert_difference("SocialTemplate.count", 1) do
      post social_templates_path, params: {
        social_template: { name: "My New Template", platform: "facebook", default_caption: "Hello!" }
      }
    end
    assert_redirected_to social_template_path(SocialTemplate.last)
  end

  test "create assigns current user as owner" do
    sign_in_as(@user)
    post social_templates_path, params: {
      social_template: { name: "Owned Template", platform: "instagram" }
    }
    assert_equal @user, SocialTemplate.last.user
  end

  test "create shows success notice" do
    sign_in_as(@user)
    post social_templates_path, params: {
      social_template: { name: "Notice Template", platform: "instagram" }
    }
    follow_redirect!
    assert_match "successfully created", response.body
  end

  test "create with invalid data renders new" do
    sign_in_as(@user)
    assert_no_difference("SocialTemplate.count") do
      post social_templates_path, params: { social_template: { name: "", platform: "instagram" } }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate name and platform renders new with error" do
    sign_in_as(@user)
    post social_templates_path, params: {
      social_template: { name: @social_template.name, platform: @social_template.platform }
    }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
  end

  # Destroy action tests
  test "destroy redirects when not signed in" do
    delete social_template_path(@social_template)
    assert_redirected_to new_session_path
  end

  test "destroy deletes the template and redirects to index" do
    sign_in_as(@user)
    assert_difference("SocialTemplate.count", -1) do
      delete social_template_path(@social_template)
    end
    assert_redirected_to social_templates_path
  end

  test "destroy shows success notice" do
    sign_in_as(@user)
    delete social_template_path(@social_template)
    follow_redirect!
    assert_match "successfully deleted", response.body
  end

  # Show page additions
  test "show has delete button" do
    sign_in_as(@user)
    get social_template_path(@social_template)
    assert_select "form[action=?][method=post]", social_template_path(@social_template)
  end

  test "index has new template link" do
    sign_in_as(@user)
    get social_templates_path
    assert_select "a[href=?]", new_social_template_path
  end
end
