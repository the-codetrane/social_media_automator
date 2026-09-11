# frozen_string_literal: true

# Copies the dimensions and duration ActiveStorage's analyzers pull out of an
# uploaded file (vips for images, ffprobe for video/audio) onto the MediaAsset
# columns the rest of the app reads.
class AnalyzeMediaAssetJob < ApplicationJob
  queue_as :default

  def perform(media_asset_id)
    asset = MediaAsset.find(media_asset_id)
    return unless asset.file.attached?

    blob = asset.file.blob
    blob.analyze unless blob.analyzed?
    metadata = blob.metadata

    # The video analyzer can report float dimensions once it has corrected for
    # the display aspect ratio; the columns are integers.
    asset.update!(
      width:             metadata["width"]&.round,
      height:            metadata["height"]&.round,
      duration_seconds:  metadata["duration"],
      last_processed_at: Time.current
    )
  end
end
