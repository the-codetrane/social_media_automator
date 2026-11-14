# frozen_string_literal: true

require "test_helper"

class SessionsHelperTest < ActionView::TestCase
  test "device_label names Chrome on macOS" do
    ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    assert_equal "Chrome on macOS", device_label(ua)
  end

  test "device_label names Safari on iOS" do
    ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    assert_equal "Safari on iOS", device_label(ua)
  end

  test "device_label prefers Edge and Firefox over Chrome and Safari tokens" do
    edge = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36 Edg/120.0"
    firefox = "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0"
    assert_equal "Edge on Windows", device_label(edge)
    assert_equal "Firefox on Linux", device_label(firefox)
  end

  test "device_label falls back to the truncated raw string" do
    assert_equal "curl/8.4.0", device_label("curl/8.4.0")
    assert_equal 40, device_label("x" * 200).length
  end

  test "device_label handles blank input" do
    assert_equal "Unknown device", device_label(nil)
    assert_equal "Unknown device", device_label("  ")
  end
end
