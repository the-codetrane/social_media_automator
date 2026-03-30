# frozen_string_literal: true

module GoogleDrive
  # Syncs all supported media files from a Google Drive folder into the local
  # MediaAsset table.
  #
  # The service pages through the entire folder (handling nextPageToken),
  # skips unsupported MIME types (Google Docs, Sheets, etc.), and upserts a
  # MediaAsset row for every image or video it finds.  Drive metadata —
  # webViewLink, webContentLink, thumbnailLink — is stored in
  # MediaAsset#raw_metadata so callers can retrieve direct-link URLs without
  # hitting the Drive API again.
  #
  # After a successful sync the ConnectedDrive#last_synced_at timestamp is
  # updated so the due_for_sync scope skips it until the configured interval
  # has elapsed.
  #
  # Usage:
  #   result = GoogleDrive::FileSyncService.new(connected_drive).call
  #   # => { synced: 12, skipped: 3 }
  class FileSyncService
    SUPPORTED_IMAGE_TYPES = %w[
      image/jpeg image/png image/gif image/webp
      image/heic image/heif image/bmp image/tiff
    ].freeze

    SUPPORTED_VIDEO_TYPES = %w[
      video/mp4 video/quicktime video/x-msvideo
      video/mpeg video/webm video/3gpp video/x-ms-wmv
    ].freeze

    SUPPORTED_MIME_TYPES = (SUPPORTED_IMAGE_TYPES + SUPPORTED_VIDEO_TYPES).freeze

    # @param connected_drive [ConnectedDrive]
    def initialize(connected_drive)
      @connected_drive = connected_drive
      @client          = GoogleDrive::ApiClient.new(connected_drive)
    end

    # Fetch every file in the configured folder and upsert MediaAsset records.
    #
    # @return [Hash] { synced: Integer, skipped: Integer }
    def call
      synced     = 0
      skipped    = 0
      page_token = nil

      loop do
        result     = @client.list_files(@connected_drive.folder_id, page_token: page_token)
        files      = result["files"] || []

        files.each do |file|
          if upsert_media_asset(file)
            synced += 1
          else
            skipped += 1
          end
        end

        page_token = result["nextPageToken"]
        break unless page_token
      end

      @connected_drive.update!(last_synced_at: Time.current)

      Rails.logger.info(
        "[GoogleDrive::FileSyncService] ConnectedDrive##{@connected_drive.id} " \
        "synced=#{synced} skipped=#{skipped}"
      )

      { synced: synced, skipped: skipped }
    end

    private

    # Create or update the MediaAsset record for a single Drive file.
    #
    # @param file [Hash] a file resource returned by the Drive API
    # @return [Boolean] true if the asset was saved, false if skipped or invalid
    def upsert_media_asset(file)
      mime_type = file["mimeType"]
      return false unless SUPPORTED_MIME_TYPES.include?(mime_type)

      asset = MediaAsset.find_or_initialize_by(external_id: file["id"])

      asset.assign_attributes(
        connected_drive: @connected_drive,
        external_name:   file["name"],
        mime_type:        mime_type,
        media_type:       media_type_for(mime_type),
        file_size:        file["size"]&.to_i,
        width:            file.dig("imageMediaMetadata", "width"),
        height:           file.dig("imageMediaMetadata", "height"),
        raw_metadata:     build_raw_metadata(file),
        first_seen_at:    asset.first_seen_at.presence || Time.current
      )

      # Preserve existing status so already-processed assets are not reset to
      # :discovered.  Only set the default for brand-new records.
      asset.status ||= :discovered

      asset.save!
      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "[GoogleDrive::FileSyncService] Skipped file id=#{file["id"]} " \
        "name=#{file["name"].inspect}: #{e.message}"
      )
      false
    end

    # Map a MIME type string to the MediaAsset media_type enum value.
    def media_type_for(mime_type)
      SUPPORTED_IMAGE_TYPES.include?(mime_type) ? :image : :video
    end

    # Build the hash stored in MediaAsset#raw_metadata.
    # Storing link fields here avoids a Drive API round-trip when the app
    # later needs the actual URLs.
    def build_raw_metadata(file)
      {
        "web_view_link"          => file["webViewLink"],
        "web_content_link"       => file["webContentLink"],
        "thumbnail_link"         => file["thumbnailLink"],
        "created_time"           => file["createdTime"],
        "image_media_metadata"   => file["imageMediaMetadata"],
        "video_media_metadata"   => file["videoMediaMetadata"]
      }.compact
    end
  end
end
