require "test_helper"

class PlatformBadgeComponentTest < ViewComponent::TestCase
  test "renders the display name and brand colour" do
    render_inline(PlatformBadgeComponent.new(platform: "youtube"))

    assert_selector "span.bg-youtube", text: "YouTube"
  end

  test "falls back for an unknown platform" do
    render_inline(PlatformBadgeComponent.new(platform: "mastodon"))

    assert_selector "span.bg-secondary", text: "Mastodon"
  end
end
