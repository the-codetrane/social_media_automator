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

  # ------------------------------------------------------------------
  # Connection state and failure recording
  # ------------------------------------------------------------------

  test "platform_connected? reflects the user's stored credentials" do
    post = planned_posts(:tiktok_draft_post)
    assert post.platform_connected?

    post.user.update!(tiktok_access_token: nil)
    assert_not post.reload.platform_connected?
  end

  test "platform_connected? uses the instagram token for facebook posts" do
    post = planned_posts(:facebook_draft_post)
    assert post.platform_connected?

    post.user.update!(instagram_access_token: nil)
    assert_not post.reload.platform_connected?
  end

  test "mark_failed! records the reason and the timestamp" do
    post = planned_posts(:tiktok_draft_post)
    post.mark_failed!("quota exhausted")

    post.reload
    assert post.failed?
    assert_equal "quota exhausted", post.failure_reason
    assert post.platform_payload["failed_at"].present?
  end

  test "mark_failed! works on a post that is itself invalid" do
    post = planned_posts(:tiktok_draft_post)
    post.update_column(:media_asset_id, media_assets(:sample_image).id)
    assert_not post.reload.valid?

    assert_nothing_raised { post.mark_failed!("not a video") }
    assert post.reload.failed?
  end

  test "mark_failed! preserves existing platform_payload keys" do
    post = planned_posts(:tiktok_draft_post)
    post.update!(platform_payload: { "privacy_level" => "SELF_ONLY" })

    post.mark_failed!("boom")

    assert_equal "SELF_ONLY", post.reload.platform_payload["privacy_level"]
    assert_equal "boom", post.failure_reason
  end

  # ------------------------------------------------------------------
  # TikTok is video-only
  # ------------------------------------------------------------------

  test "a tiktok post is invalid with an image media asset" do
    post = PlannedPost.new(
      user:         users(:one),
      media_asset:  media_assets(:sample_image),
      platform:     :tiktok,
      status:       :draft
    )

    assert_not post.valid?
    assert_includes post.errors[:media_asset], "must be a video — TikTok does not support image posts"
  end

  test "a tiktok post is valid with a video media asset" do
    post = PlannedPost.new(
      user:         users(:one),
      media_asset:  media_assets(:sample_video),
      platform:     :tiktok,
      status:       :draft
    )

    assert post.valid?, post.errors.full_messages.to_sentence
  end

  test "other platforms still accept image media assets" do
    %i[instagram facebook youtube].each do |platform|
      post = PlannedPost.new(
        user:        users(:one),
        media_asset: media_assets(:sample_image),
        platform:    platform,
        status:      :draft
      )
      assert post.valid?, "#{platform} should accept an image: #{post.errors.full_messages.to_sentence}"
    end
  end

  test "switching an existing tiktok post to an image asset is rejected" do
    post = planned_posts(:tiktok_draft_post)
    post.media_asset = media_assets(:sample_image)

    assert_not post.valid?
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

  # ---------------------------------------------------------------------------
  # .collaborator_suggestions
  # ---------------------------------------------------------------------------

  test "collaborator_suggestions counts usage across the user's instagram posts" do
    user = users(:one)
    planned_posts(:draft_post).update!(platform_payload: { "collaborators" => [ "chef_alex", "bakery_co" ] })
    planned_posts(:carousel_post).update!(
      platform_payload: planned_posts(:carousel_post).platform_payload.merge("collaborators" => [ "chef_alex" ])
    )

    suggestions = PlannedPost.collaborator_suggestions(user)

    assert_equal({ username: "chef_alex", count: 2 }, suggestions.first)
    assert_includes suggestions, { username: "bakery_co", count: 1 }
  end

  test "collaborator_suggestions filters by a case-insensitive query" do
    user = users(:one)
    planned_posts(:draft_post).update!(platform_payload: { "collaborators" => [ "chef_alex", "bakery_co" ] })

    assert_equal [ "chef_alex" ], PlannedPost.collaborator_suggestions(user, query: "CHEF").map { |s| s[:username] }
    assert_equal [ "chef_alex" ], PlannedPost.collaborator_suggestions(user, query: "@chef").map { |s| s[:username] }
  end

  test "collaborator_suggestions ignores other users and other platforms" do
    planned_posts(:draft_post).update!(platform_payload: { "collaborators" => [ "chef_alex" ] })
    planned_posts(:youtube_draft_post).update!(platform_payload: { "collaborators" => [ "youtube_person" ] })

    usernames = PlannedPost.collaborator_suggestions(users(:one)).map { |s| s[:username] }

    assert_includes usernames, "chef_alex"
    assert_not_includes usernames, "youtube_person"
    assert_empty PlannedPost.collaborator_suggestions(users(:admin))
  end

  test "collaborator_suggestions returns an empty array when there is no history" do
    assert_empty PlannedPost.collaborator_suggestions(users(:one))
  end

  test "collaborator_suggestions honours the limit" do
    planned_posts(:draft_post).update!(platform_payload: { "collaborators" => %w[a b c] })

    assert_equal 2, PlannedPost.collaborator_suggestions(users(:one), limit: 2).size
  end
end
