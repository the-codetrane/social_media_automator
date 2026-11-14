require "application_system_test_case"

# Exercises the collaborators combobox (library multi-value mode) in a browser:
# suggestions, free-text entry, chip removal and the max.
class CollaboratorPickerTest < ApplicationSystemTestCase
  setup do
    @planned_post = planned_posts(:draft_post)

    planned_posts(:carousel_post).update!(
      platform_payload: planned_posts(:carousel_post).platform_payload.merge(
        "collaborators" => [ "chef_alex", "bakery_co" ]
      )
    )

    sign_in_through_form(users(:one))
  end

  test "suggests previously used collaborators and adds the chosen one" do
    visit edit_planned_post_path(@planned_post)

    fill_in_and_confirm "Collaborators", with: "chef"
    find("[role='option']", text: "chef_alex").click
    assert_button "Remove chef_alex"

    click_on "Save Changes"

    assert_current_path planned_post_path(@planned_post)
    assert_equal [ "chef_alex" ], @planned_post.reload.platform_payload["collaborators"]
  end

  test "adds a username that has never been used, stripping the @" do
    visit edit_planned_post_path(@planned_post)

    fill_in_and_confirm "Collaborators", with: "@brand_new_account"
    find_field("Collaborators").send_keys(:enter)
    assert_button "Remove @brand_new_account"

    click_on "Save Changes"

    assert_current_path planned_post_path(@planned_post)
    assert_equal [ "brand_new_account" ], @planned_post.reload.platform_payload["collaborators"]
  end

  test "removes a collaborator with the chip's remove button" do
    @planned_post.update!(platform_payload: { "collaborators" => [ "chef_alex", "bakery_co" ] })
    visit edit_planned_post_path(@planned_post)

    click_button "Remove chef_alex"
    assert_no_button "Remove chef_alex"

    click_on "Save Changes"

    assert_current_path planned_post_path(@planned_post)
    assert_equal [ "bakery_co" ], @planned_post.reload.platform_payload["collaborators"]
  end
end
