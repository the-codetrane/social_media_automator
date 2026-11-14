require "test_helper"

class IntegrationCardComponentTest < ViewComponent::TestCase
  test "shows the account and a Connected badge when connected" do
    render_inline(IntegrationCardComponent.new(name: "YouTube Channel", connected: true, account: "Cain Channel")) do
      "actions"
    end

    assert_selector "h2", text: "YouTube Channel"
    assert_selector "p", text: "Cain Channel"
    assert_selector "span", text: "Connected"
    assert_text "actions"
  end

  test "hides the account and says Not connected when disconnected" do
    render_inline(IntegrationCardComponent.new(name: "TikTok Account", connected: false, account: "@stale"))

    assert_selector "span", text: "Not connected"
    assert_no_text "@stale"
  end

  test "renders the logo hidden from assistive technology, and the details slot" do
    render_inline(IntegrationCardComponent.new(name: "TikTok Account", connected: false)) do |card|
      card.with_logo { "LOGO" }
      card.with_details { "Environment" }
    end

    assert_selector "[aria-hidden=true]", text: "LOGO"
    assert_text "Environment"
  end
end
