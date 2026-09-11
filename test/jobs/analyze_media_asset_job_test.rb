require "test_helper"

class AnalyzeMediaAssetJobTest < ActiveJob::TestCase
  test "copies analyzed image dimensions onto the asset" do
    blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("test_image.png").open, filename: "test_image.png", content_type: "image/png")
    asset = MediaAsset.create!(external_id: "upload-1", media_type: :image, status: :processed, first_seen_at: Time.current)
    asset.file.attach(blob)

    AnalyzeMediaAssetJob.perform_now(asset.id)
    asset.reload
    blob.reload

    assert blob.analyzed?
    assert_equal blob.metadata["width"], asset.width
    assert_equal blob.metadata["height"], asset.height
    assert asset.width.positive?
    assert_nil asset.duration_seconds
    assert asset.last_processed_at.present?
  end

  test "does nothing for an asset without a file" do
    asset = media_assets(:sample_image)
    AnalyzeMediaAssetJob.perform_now(asset.id)
    assert_equal 1080, asset.reload.width
  end
end
