# frozen_string_literal: true

require "test_helper"

class ConnectedDriveTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  test "fixtures are valid" do
    assert connected_drives(:personal_drive).valid?
    assert connected_drives(:secondary_drive).valid?
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  test "is invalid without a name" do
    drive = connected_drives(:personal_drive)
    drive.name = nil
    assert_not drive.valid?
    assert_includes drive.errors[:name], "can't be blank"
  end

  test "is invalid without a folder_id" do
    drive = connected_drives(:personal_drive)
    drive.folder_id = nil
    assert_not drive.valid?
    assert_includes drive.errors[:folder_id], "can't be blank"
  end

  test "is invalid with an unknown provider" do
    drive = connected_drives(:personal_drive)
    drive.provider = "dropbox"
    assert_not drive.valid?
    assert_includes drive.errors[:provider], "is not included in the list"
  end

  test "is invalid without sync_interval_minutes" do
    drive = connected_drives(:personal_drive)
    drive.sync_interval_minutes = nil
    assert_not drive.valid?
  end

  test "is invalid with non-positive sync_interval_minutes" do
    drive = connected_drives(:personal_drive)
    drive.sync_interval_minutes = 0
    assert_not drive.valid?
  end

  test "enforces uniqueness of folder_id scoped to provider" do
    duplicate = ConnectedDrive.new(
      name: "Dupe Drive",
      provider: connected_drives(:personal_drive).provider,
      folder_id: connected_drives(:personal_drive).folder_id,
      sync_interval_minutes: 60,
      user: users(:one)
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:folder_id], "has already been taken"
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "has many media_assets" do
    assert_respond_to connected_drives(:personal_drive), :media_assets
  end

  test "belongs to user" do
    assert_respond_to connected_drives(:personal_drive), :user
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------
  test "#token_expired? returns true when token_expires_at is in the past" do
    drive = connected_drives(:personal_drive)
    drive.token_expires_at = 1.minute.ago
    assert drive.token_expired?
  end

  test "#token_expired? returns false when token_expires_at is in the future" do
    drive = connected_drives(:personal_drive)
    drive.token_expires_at = 1.hour.from_now
    assert_not drive.token_expired?
  end

  test "#token_expired? returns false when token_expires_at is nil" do
    drive = connected_drives(:personal_drive)
    drive.token_expires_at = nil
    assert_not drive.token_expired?
  end

  test "#synced_recently? returns true when last_synced_at is within interval" do
    drive = connected_drives(:personal_drive)
    drive.last_synced_at = 30.minutes.ago
    drive.sync_interval_minutes = 60
    assert drive.synced_recently?
  end

  test "#synced_recently? returns false when last_synced_at is beyond interval" do
    drive = connected_drives(:personal_drive)
    drive.last_synced_at = 2.hours.ago
    drive.sync_interval_minutes = 60
    assert_not drive.synced_recently?
  end

  test "#synced_recently? returns false when last_synced_at is nil" do
    drive = connected_drives(:secondary_drive)
    assert_not drive.synced_recently?
  end
end
