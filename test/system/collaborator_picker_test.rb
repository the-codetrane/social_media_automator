require "application_system_test_case"

# Exercises the collaborator chip input for real, in a browser: the suggestion
# dropdown, free-text entry, chip removal and the hidden inputs that carry the
# usernames back to the server.
class CollaboratorPickerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @planned_post = planned_posts(:draft_post)

    # Give the account some collaborator history for the typeahead to find.
    planned_posts(:carousel_post).update!(
      platform_payload: planned_posts(:carousel_post).platform_payload.merge(
        "collaborators" => [ "chef_alex", "bakery_co" ]
      )
    )

    sign_in_through_form(@user)
  end

  test "suggests previously used collaborators and adds the chosen one" do
    visit_edit_page expecting_count: 0

    find_field("Collaborators").click
    fill_in_collaborator "chef"

    assert_selector "[data-collaborator-select-target='suggestions'] button", text: "@chef_alex"

    find("[data-collaborator-select-target='suggestions'] button", text: "@chef_alex").click

    assert_selector "[data-collaborator-select-target='chips']", text: "@chef_alex"
    assert_counter 1
  end

  test "adds a username that has never been used before" do
    visit_edit_page expecting_count: 0

    fill_in_collaborator "brand_new_account"
    press_enter_in_collaborator_field

    assert_selector "[data-collaborator-select-target='chips']", text: "@brand_new_account"

    click_on "Save Changes"

    assert_current_path planned_post_path(@planned_post)
    assert_equal [ "brand_new_account" ], @planned_post.reload.platform_payload["collaborators"]
  end

  test "strips an @ prefix and stops at three collaborators" do
    visit_edit_page expecting_count: 0

    %w[@one two three].each do |username|
      fill_in_collaborator username
      press_enter_in_collaborator_field
    end

    assert_selector "[data-collaborator-select-target='chips'] span", text: "@one"
    assert_counter 3

    # The input disables itself rather than letting a 4th through to the server,
    # which would be rejected by Instagram::PublishOptions.
    assert find_field("Collaborators", disabled: true).disabled?
  end

  test "removes a collaborator with the chip's remove button" do
    @planned_post.update!(platform_payload: { "collaborators" => [ "chef_alex", "bakery_co" ] })
    visit_edit_page expecting_count: 2

    find("button[aria-label='Remove chef_alex']").click

    assert_no_selector "[data-collaborator-select-target='chips']", text: "@chef_alex"
    assert_selector "[data-collaborator-select-target='chips']", text: "@bakery_co"

    click_on "Save Changes"

    assert_current_path planned_post_path(@planned_post)
    assert_equal [ "bakery_co" ], @planned_post.reload.platform_payload["collaborators"]
  end

  private

  # The counter is filled in by the collaborator-select controller on connect,
  # so waiting for it also waits for the controller. Typing or clicking before
  # then would hit an input with no Stimulus actions bound (Enter would submit
  # the form, a chip's remove button would not exist yet).
  def visit_edit_page(expecting_count:)
    visit edit_planned_post_path(@planned_post)
    assert_counter expecting_count
  end

  def assert_counter(count)
    assert_selector "[data-collaborator-select-target='counter']", exact_text: "#{count} of 3"
  end

  # Waits for the value to land (and re-types it if it did not) before the
  # next step; a bare set() races the debounced suggestion fetch under load.
  def fill_in_collaborator(value)
    fill_in_and_confirm "Collaborators", with: value
  end

  def press_enter_in_collaborator_field
    find_field("Collaborators").send_keys(:enter)
  end
end
