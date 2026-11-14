require "test_helper"

class StatusBadgeComponentTest < ViewComponent::TestCase
  test "maps post statuses to variants" do
    render_inline(StatusBadgeComponent.new(status: "published"))

    assert_selector "span.bg-success", text: "Published"
  end

  test "maps media statuses to variants" do
    render_inline(StatusBadgeComponent.new(status: "discovered", kind: :media))

    assert_selector "span.bg-warning", text: "Discovered"
  end

  test "unknown status is secondary" do
    render_inline(StatusBadgeComponent.new(status: "weird"))

    assert_selector "span.bg-secondary", text: "Weird"
  end
end
