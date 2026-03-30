# frozen_string_literal: true

# Syncs a single ConnectedDrive in the background by calling
# GoogleDrive::FileSyncService.
#
# Enqueue it like this:
#   SyncGoogleDriveJob.perform_later(connected_drive.id)
#
# Or let the due_for_sync scope drive a scheduled sweep:
#   ConnectedDrive.due_for_sync.each do |drive|
#     SyncGoogleDriveJob.perform_later(drive.id)
#   end
#
# Retries:
# - GoogleDrive::ApiError            → retried 3× with polynomial back-off
# - GoogleDrive::TokenRefreshError   → retried 2× with a 5-minute wait
# - Other GoogleDrive::Error         → discarded after retries are exhausted
class SyncGoogleDriveJob < ApplicationJob
  queue_as :default

  # Define discard_on FIRST so it has the lowest priority.
  # Rails rescue_from checks handlers in reverse registration order, so handlers
  # defined later (retry_on below) take precedence over this catch-all.
  # This means ApiError and TokenRefreshError are retried, while any other
  # GoogleDrive::Error is discarded immediately.
  discard_on(GoogleDrive::Error) do |job, error|
    Rails.logger.error(
      "[SyncGoogleDriveJob] Permanently failed for " \
      "ConnectedDrive##{job.arguments.first}: #{error.message}"
    )
  end

  retry_on GoogleDrive::ApiError,          wait: :polynomially_longer, attempts: 3
  retry_on GoogleDrive::TokenRefreshError, wait: 5.minutes,            attempts: 2

  # @param connected_drive_id [Integer]
  def perform(connected_drive_id)
    drive = ConnectedDrive.find(connected_drive_id)

    if drive.synced_recently?
      Rails.logger.info(
        "[SyncGoogleDriveJob] ConnectedDrive##{connected_drive_id} " \
        "synced recently (interval: #{drive.sync_interval_minutes} min), skipping."
      )
      return
    end

    result = GoogleDrive::FileSyncService.new(drive).call

    Rails.logger.info(
      "[SyncGoogleDriveJob] ConnectedDrive##{connected_drive_id} " \
      "complete — synced=#{result[:synced]} skipped=#{result[:skipped]}"
    )
  end
end
