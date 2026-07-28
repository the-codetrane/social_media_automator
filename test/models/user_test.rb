require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  # ------------------------------------------------------------------
  # TikTok credentials
  # ------------------------------------------------------------------

  test "tiktok_connected? requires both an access token and an open_id" do
    user = users(:one)
    assert user.tiktok_connected?

    user.tiktok_open_id = nil
    assert_not user.tiktok_connected?

    user.tiktok_open_id      = "open_id"
    user.tiktok_access_token = nil
    assert_not user.tiktok_connected?
  end

  test "tiktok_token_expired? is true only once the access token lapses" do
    user = users(:one)
    assert_not user.tiktok_token_expired?

    user.tiktok_token_expires_at = 1.minute.ago
    assert user.tiktok_token_expired?
  end

  test "tiktok_token_expiring? uses a minutes-wide buffer for the 24-hour token" do
    user = users(:one)
    assert_not user.tiktok_token_expiring?

    user.tiktok_token_expires_at = 2.minutes.from_now
    assert user.tiktok_token_expiring?
  end

  test "tiktok_token_expiring? is true when the user is not connected" do
    assert users(:two).tiktok_token_expiring?
  end

  test "tiktok_refresh_expired? flags a lapsed 365-day refresh token" do
    user = users(:one)
    assert_not user.tiktok_refresh_expired?

    user.tiktok_refresh_expires_at = 1.day.ago
    assert user.tiktok_refresh_expired?
  end
end
