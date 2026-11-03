require "application_system_test_case"

class FocusProbeTest < ApplicationSystemTestCase
  test "page focus after sign-in" do
    sign_in_through_form(users(:one))
    visit edit_planned_post_path(planned_posts(:draft_post))
    samples = 20.times.map { |i| sleep 0.5; [ (i + 1) * 0.5, page.evaluate_script("document.hasFocus()") ] }
    puts "\nFOCUS: " + samples.map { |t, f| "#{t}s=#{f}" }.join(" ")
    puts "CHROME: " + page.driver.browser.capabilities.browser_version.to_s
  end
end
