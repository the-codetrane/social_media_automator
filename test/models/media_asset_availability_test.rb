# frozen_string_literal: true

require "test_helper"

# Archiving (soft delete), publication tracking and reuse warnings for media
# assets. Fixtures already put sample_image and sample_video on scheduled
# posts, so these tests use assets that start out available.
class MediaAssetAvailabilityTest < ActiveSupport::TestCase
  setup do
    @user  = users(:one)
    @asset = media_assets(:geocoded_image)
    @other = media_assets(:sample_image_2)
  end

  def build_post(asset:, status: :draft, carousel: nil, **attrs)
    payload = carousel ? { "carousel_asset_ids" => carousel.map(&:id) } : nil
    PlannedPost.create!(
      user: @user, platform: :instagram, media_asset: asset, status: status,
      scheduled_at: (2.days.from_now if status == :scheduled),
      platform_payload: payload, **attrs
    )
  end

  # --- availability --------------------------------------------------------

  test "an unused asset is available" do
    assert_equal "available", @asset.availability
    assert_includes MediaAsset.available, @asset
  end

  test "archive! hides the asset from available and restores on unarchive!" do
    @asset.archive!

    assert @asset.archived?
    assert_equal "archived", @asset.availability
    assert_includes MediaAsset.archived, @asset
    assert_not_includes MediaAsset.available, @asset

    @asset.unarchive!
    assert_not @asset.reload.archived?
    assert_includes MediaAsset.available, @asset
  end

  test "archiving does not change the processing status" do
    @asset.archive!
    assert @asset.reload.processed?
  end

  test "an asset on a scheduled post is reserved" do
    build_post(asset: @asset, status: :scheduled)

    assert_equal "reserved", @asset.availability
    assert_includes MediaAsset.reserved, @asset
    assert_not_includes MediaAsset.available, @asset
  end

  test "carousel members of a scheduled post are reserved" do
    build_post(asset: @asset, status: :scheduled, carousel: [ @asset, @other ])

    assert_includes MediaAsset.reserved, @other
    assert_not_includes MediaAsset.available, @other
  end

  test "an asset on a draft post is not reserved" do
    build_post(asset: @asset, status: :draft)
    assert_includes MediaAsset.available, @asset
  end

  test "a post does not reserve its own assets" do
    post = build_post(asset: @asset, status: :scheduled)

    assert_equal "available", @asset.availability(excluding: post)
    assert_includes MediaAsset.available(excluding: post), @asset
  end

  test "with_availability filters by bucket and passes everything through for all" do
    @other.update!(published_at: 1.day.ago)
    @asset.archive!

    assert_includes MediaAsset.with_availability("published"), @other
    assert_includes MediaAsset.with_availability("archived"), @asset
    assert_not_includes MediaAsset.with_availability("available"), @asset
    assert_equal MediaAsset.count, MediaAsset.with_availability("all").count
  end

  # --- publication ---------------------------------------------------------

  test "publishing a post stamps its assets, including carousel members" do
    post = build_post(asset: @asset, carousel: [ @asset, @other ])
    published_at = 1.minute.ago

    post.update!(status: :published, published_at: published_at)

    assert_in_delta published_at, @asset.reload.published_at, 1.second
    assert_in_delta published_at, @other.reload.published_at, 1.second
    assert_equal "published", @asset.availability
  end

  test "publishing again keeps the first published date" do
    first = 3.days.ago
    @asset.update!(published_at: first)

    build_post(asset: @asset).update!(status: :published, published_at: 1.minute.ago)

    assert_in_delta first, @asset.reload.published_at, 1.second
  end

  test "non-publish status changes do not stamp assets" do
    build_post(asset: @asset).mark_failed!("boom")
    assert_nil @asset.reload.published_at
  end

  # --- posts_using ---------------------------------------------------------

  test "posts_using finds primary and carousel usage" do
    primary  = build_post(asset: @asset)
    carousel = build_post(asset: @other, carousel: [ @other, @asset ])

    assert_equal [ primary.id, carousel.id ].sort, @asset.posts_using.pluck(:id).sort
  end

  # --- reuse warnings ------------------------------------------------------

  test "no warnings for available assets" do
    assert_empty build_post(asset: @asset).media_asset_reuse_warnings
  end

  test "warns about archived, published and reserved assets" do
    archived = media_assets(:sample_long_video)
    archived.archive!
    @other.update!(published_at: Time.zone.parse("2026-10-01 12:00"))
    build_post(asset: @asset, status: :scheduled)

    draft = build_post(asset: @asset, carousel: [ @asset, @other, archived ])
    warnings = draft.media_asset_reuse_warnings

    assert_equal 3, warnings.size
    assert(warnings.any? { |w| w.include?("feature.mp4 is archived") })
    assert(warnings.any? { |w| w.include?("sunrise.jpg was already published on October 1, 2026") })
    assert(warnings.any? { |w| w.include?("sf_photo.jpg is also on another scheduled post") })
  end

  test "a published post has no reuse warnings about itself" do
    post = build_post(asset: @asset)
    post.update!(status: :published, published_at: 1.minute.ago)

    assert_empty post.reload.media_asset_reuse_warnings
  end

  # --- deletion guard ------------------------------------------------------

  test "an asset with posts cannot be hard-deleted" do
    build_post(asset: @asset)

    assert_not @asset.destroy
    assert MediaAsset.exists?(@asset.id)
  end
end
