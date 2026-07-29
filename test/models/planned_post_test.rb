# frozen_string_literal: true

require "test_helper"

class PlannedPostTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  test "fixtures are valid" do
    assert planned_posts(:draft_post).valid?
    assert planned_posts(:scheduled_post).valid?
    assert planned_posts(:published_post).valid?
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  test "is invalid without a platform" do
    post = planned_posts(:draft_post)
    post.platform = nil
    assert_not post.valid?
    assert_includes post.errors[:platform], "can't be blank"
  end

  test "is invalid without a status" do
    post = planned_posts(:draft_post)
    # Force nil status by writing raw attribute
    post.write_attribute(:status, nil)
    assert_not post.valid?
  end

  test "scheduled post requires scheduled_at" do
    post = planned_posts(:draft_post)
    post.status = :scheduled
    post.scheduled_at = nil
    assert_not post.valid?
    assert_includes post.errors[:scheduled_at], "can't be blank"
  end

  test "scheduled_at must be in the future for scheduled posts" do
    post = planned_posts(:scheduled_post)
    post.scheduled_at = 1.hour.ago
    assert_not post.valid?
    assert_includes post.errors[:scheduled_at], "must be in the future"
  end

  test "published_at cannot be in the future for published posts" do
    post = planned_posts(:published_post)
    post.published_at = 1.day.from_now
    assert_not post.valid?
    assert_includes post.errors[:published_at], "cannot be in the future"
  end

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  test "platform enum has correct values" do
    assert_equal 0, PlannedPost.platforms[:instagram]
    assert_equal 1, PlannedPost.platforms[:youtube]
    assert_equal 2, PlannedPost.platforms[:facebook]
    assert_equal 3, PlannedPost.platforms[:tiktok]
  end

  test "status enum has correct values" do
    assert_equal 0, PlannedPost.statuses[:draft]
    assert_equal 1, PlannedPost.statuses[:scheduled]
    assert_equal 2, PlannedPost.statuses[:published]
    assert_equal 3, PlannedPost.statuses[:failed]
    assert_equal 4, PlannedPost.statuses[:canceled]
  end

  test "draft_post has status draft" do
    assert planned_posts(:draft_post).draft?
  end

  test "scheduled_post has status scheduled" do
    assert planned_posts(:scheduled_post).scheduled?
  end

  test "published_post has status published" do
    assert planned_posts(:published_post).published?
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test ".upcoming returns scheduled posts with future scheduled_at" do
    PlannedPost.upcoming.each do |post|
      assert post.scheduled?
      assert post.scheduled_at > Time.current
    end
  end

  test ".for_platform returns posts for the given platform" do
    PlannedPost.for_platform(:instagram).each { |p| assert p.instagram? }
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs to media_asset" do
    assert_respond_to planned_posts(:draft_post), :media_asset
    assert_not_nil planned_posts(:draft_post).media_asset
  end

  test "belongs to social_template optionally" do
    assert planned_posts(:published_post).valid?
    assert_nil planned_posts(:published_post).social_template_id
  end

  test "belongs to user" do
    assert_respond_to planned_posts(:draft_post), :user
  end
end
