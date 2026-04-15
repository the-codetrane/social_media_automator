# frozen_string_literal: true

require "test_helper"

class MediaAssetTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  test "fixtures are valid" do
    assert media_assets(:sample_image).valid?
    assert media_assets(:sample_video).valid?
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  test "is invalid without an external_id" do
    asset = media_assets(:sample_image)
    asset.external_id = nil
    assert_not asset.valid?
    assert_includes asset.errors[:external_id], "can't be blank"
  end

  test "enforces uniqueness of external_id" do
    duplicate = MediaAsset.new(
      external_id: media_assets(:sample_image).external_id,
      media_type: :image,
      status: :discovered,
      first_seen_at: Time.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:external_id], "has already been taken"
  end

  test "is invalid without first_seen_at" do
    asset = media_assets(:sample_image)
    asset.first_seen_at = nil
    assert_not asset.valid?
    assert_includes asset.errors[:first_seen_at], "can't be blank"
  end

  test "is invalid with a non-positive file_size" do
    asset = media_assets(:sample_image)
    asset.file_size = 0
    assert_not asset.valid?
  end

  test "allows nil file_size" do
    asset = media_assets(:sample_image)
    asset.file_size = nil
    assert asset.valid?
  end

  test "is invalid with a non-positive duration_seconds" do
    asset = media_assets(:sample_video)
    asset.duration_seconds = -1
    assert_not asset.valid?
  end

  test "allows nil duration_seconds" do
    asset = media_assets(:sample_image)
    assert_nil asset.duration_seconds
    assert asset.valid?
  end

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  test "media_type enum has correct values" do
    assert_equal 0, MediaAsset.media_types[:image]
    assert_equal 1, MediaAsset.media_types[:video]
  end

  test "status enum has correct values" do
    assert_equal 0, MediaAsset.statuses[:discovered]
    assert_equal 1, MediaAsset.statuses[:processed]
    assert_equal 2, MediaAsset.statuses[:failed]
    assert_equal 3, MediaAsset.statuses[:archived]
  end

  test "sample_image has media_type image" do
    assert media_assets(:sample_image).image?
  end

  test "sample_video has media_type video" do
    assert media_assets(:sample_video).video?
  end

  test "sample_video has status processed" do
    assert media_assets(:sample_video).processed?
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test ".images scope returns only images" do
    MediaAsset.images.each { |a| assert a.image? }
  end

  test ".videos scope returns only videos" do
    MediaAsset.videos.each { |a| assert a.video? }
  end

  test ".ready scope returns only processed assets" do
    MediaAsset.ready.each { |a| assert a.processed? }
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "has many planned_posts" do
    assert_respond_to media_assets(:sample_image), :planned_posts
  end

  # ---------------------------------------------------------------------------
  # #public_url
  # ---------------------------------------------------------------------------
  test "public_url returns URL from raw_metadata when file not attached" do
    asset = media_assets(:sample_image)
    assert_equal "https://cdn.example.com/sunset.jpg", asset.public_url
  end

  test "public_url returns nil when raw_metadata is empty and file not attached" do
    asset = media_assets(:sample_image_no_url)
    assert_nil asset.public_url
  end

  test "public_url? returns true when URL is present" do
    asset = media_assets(:sample_image)
    assert asset.public_url?
  end

  test "public_url? returns false when URL is nil" do
    asset = media_assets(:sample_image_no_url)
    assert_not asset.public_url?
  end

  test "public_url parses raw_metadata string if needed" do
    asset = media_assets(:sample_image)
    asset.raw_metadata = '{"public_url": "https://example.com/test.jpg"}'
    assert_equal "https://example.com/test.jpg", asset.public_url
  end

  test "has_one_attached :file" do
    assert_respond_to media_assets(:sample_image), :file
  end
end
