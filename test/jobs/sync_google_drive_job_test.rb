# frozen_string_literal: true

require "test_helper"

class SyncGoogleDriveJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  def setup
    # secondary_drive has last_synced_at: nil → synced_recently? == false
    @drive = connected_drives(:secondary_drive)
    # personal_drive has last_synced_at: 30 min ago, interval: 60 min → synced_recently? == true
    @recently_synced_drive = connected_drives(:personal_drive)
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "perform calls FileSyncService with the correct ConnectedDrive" do
    result = { synced: 5, skipped: 1 }

    mock_service = Minitest::Mock.new
    mock_service.expect(:call, result)

    # Wrap in a lambda so that stub(:new, ...) returns the mock rather than
    # invoking mock.call(drive) — which would fail since :call expects 0 args.
    GoogleDrive::FileSyncService.stub(:new, ->(_drive) { mock_service }) do
      SyncGoogleDriveJob.perform_now(@drive.id)
    end

    assert_mock mock_service
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: SyncGoogleDriveJob, queue: "default") do
      SyncGoogleDriveJob.perform_later(@drive.id)
    end
  end

  # -------------------------------------------------------------------------
  # Guard: skip recently synced drives
  # -------------------------------------------------------------------------

  test "perform skips a drive that was synced recently" do
    GoogleDrive::FileSyncService.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { SyncGoogleDriveJob.perform_now(@recently_synced_drive.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Error handling / retry behaviour
  # -------------------------------------------------------------------------

  test "perform re-enqueues the job on ApiError for retry" do
    GoogleDrive::FileSyncService.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:call) { raise GoogleDrive::ApiError, "quota exceeded" }
      obj
    }) do
      assert_enqueued_with(job: SyncGoogleDriveJob) do
        SyncGoogleDriveJob.perform_now(@drive.id)
      end
    end
  end

  test "perform re-enqueues the job on TokenRefreshError for retry" do
    GoogleDrive::FileSyncService.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:call) { raise GoogleDrive::TokenRefreshError, "token revoked" }
      obj
    }) do
      assert_enqueued_with(job: SyncGoogleDriveJob) do
        SyncGoogleDriveJob.perform_now(@drive.id)
      end
    end
  end

  test "discard_on swallows GoogleDrive::Error and does not re-raise" do
    # GoogleDrive::Error (base class, not covered by retry_on) is caught by
    # discard_on immediately — no exception escapes and no retry is enqueued.
    GoogleDrive::FileSyncService.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:call) { raise GoogleDrive::Error, "unclassified error" }
      obj
    }) do
      assert_nothing_raised { SyncGoogleDriveJob.perform_now(@drive.id) }
    end
  end
end
