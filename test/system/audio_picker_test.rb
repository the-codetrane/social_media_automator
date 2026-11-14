require "application_system_test_case"

class AudioPickerTest < ApplicationSystemTestCase
  setup { sign_in_through_form(users(:one)) }

  test "the edit page connects every Stimulus controller without errors" do
    page.driver.browser.logs.get(:browser) # discard sign-in noise
    visit edit_planned_post_path(planned_posts(:draft_post))
    assert_selector "[role='combobox'][aria-label='Collaborators'], [role='combobox'][id='collaborator_input']"

    errors = page.driver.browser.logs.get(:browser).map(&:message).grep(/Error connecting controller/)
    assert_empty errors
  end
end
