require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # System tests inherit parallelize(workers: :number_of_processors) from
  # ActiveSupport::TestCase, which puts one headless Chrome per worker on the
  # machine at once. The contention makes sign-in intermittently exceed
  # Capybara's wait, so browser tests run serially.
  parallelize(workers: 1)

  # Sign in through the real form, then wait for the redirect to land —
  # click_on does not wait on its own, so the next visit can otherwise race the
  # in-flight Turbo navigation and arrive unauthenticated.
  def sign_in_through_form(user, password: "password")
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: password
    click_on "Sign in"

    assert_button "Sign out", wait: 15
  end
end
