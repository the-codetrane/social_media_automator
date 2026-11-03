require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # Every test signs in with the password "password". After a sign-in Chrome
    # checks the credential against Google's leak database and can raise a
    # "Change your password" / "Save password?" prompt, which takes keyboard
    # focus from the page while the page still looks focused. That fits the
    # intermittent CI failures where the first keystrokes or click after
    # signing in were lost; the prompt only appears after a network round
    # trip, so it came and went. Tests never need the password manager.
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
  end

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
    fill_in_and_confirm "Email address", with: user.email_address
    fill_in_and_confirm "Password", with: password
    click_on "Sign in"

    assert_button "Sign out", wait: 15
  end

  # fill_in, then wait for the value to actually be in the field and re-type
  # it if it is not — a safety net in case keystrokes sent right after a page
  # load are dropped, which would otherwise leave the field empty and fail
  # later with a confusing error.
  def fill_in_and_confirm(locator, with:, attempts: 3)
    attempts.times do
      fill_in locator, with: with
      return if has_field?(locator, with: with, wait: 2)
    end

    assert_field locator, with: with
  end
end
