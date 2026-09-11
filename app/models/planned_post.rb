# frozen_string_literal: true

class PlannedPost < ApplicationRecord
  enum :platform, { instagram: 0, youtube: 1, facebook: 2, tiktok: 3 }
  enum :status, { draft: 0, scheduled: 1, published: 2, failed: 3, canceled: 4 }

  belongs_to :media_asset
  belongs_to :social_template, optional: true
  belongs_to :user

  validates :platform, presence: true
  validates :status, presence: true
  validates :scheduled_at, presence: true, if: :scheduled?
  validate :published_at_not_in_future, if: :published?
  validate :scheduled_at_in_future, if: :scheduled?
  validate :tiktok_requires_video_asset, if: :tiktok?
  validate :story_supported_on_platform, if: :story?
  validate :story_requires_single_visual_asset, if: :story?
  validate :story_media_within_platform_limits, if: :story?

  scope :upcoming, -> { where(status: :scheduled).where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :for_platform, ->(platform) { where(platform: platform) }

  # True when the account this post publishes to has completed its OAuth
  # connection.  Publishing without one burns the post: the API client raises
  # immediately and the job discards it as failed.
  def platform_connected?
    case platform
    when "instagram", "facebook" then user.instagram_connected?
    when "tiktok"                then user.tiktok_connected?
    when "youtube"               then YouTube::AuthService.new.connected?
    else false
    end
  end

  # Instagram usernames this user has tagged as collaborators before, most
  # frequently used first.
  #
  # Instagram has no username search API, so the edit form's collaborator
  # typeahead suggests from the user's own history instead. Free-text entry
  # stays available for handles that have never been used.
  #
  # @param user [User]
  # @param query [String, nil] case-insensitive substring filter
  # @param limit [Integer]
  # @return [Array<Hash>] { username:, count: }, most used first
  def self.collaborator_suggestions(user, query: nil, limit: 10)
    counts = Hash.new(0)

    instagram
      .where(user: user)
      .where.not(platform_payload: nil)
      .pluck(:platform_payload)
      .each do |payload|
        next unless payload.is_a?(Hash)

        Array(payload["collaborators"]).each do |name|
          username = name.to_s.strip.delete_prefix("@")
          counts[username] += 1 if username.present?
        end
      end

    filter = query.to_s.strip.delete_prefix("@").downcase
    counts = counts.select { |username, _| username.downcase.include?(filter) } if filter.present?

    counts
      .sort_by { |username, count| [ -count, username ] }
      .first(limit)
      .map { |username, count| { username: username, count: count } }
  end

  # Record a failure without validating, keeping the reason on the record.
  #
  # validate: false matters because the post may be invalid for the very reason
  # it failed (a TikTok post whose asset is not a video) — update! would raise
  # and update would silently no-op, stranding it in its previous status.
  def mark_failed!(reason = nil)
    self.status = :failed

    if reason.present?
      self.platform_payload = platform_payload.to_h.merge(
        "failure_reason" => reason.to_s.truncate(500),
        "failed_at"      => Time.current.iso8601
      )
    end

    save(validate: false)
  end

  # The last recorded reason this post failed to publish, if any.
  def failure_reason
    platform_payload&.dig("failure_reason")
  end

  # Which shape this post publishes as: "story", "carousel" or "single".
  #
  # Story is an explicit choice recorded in platform_payload — it cannot be
  # inferred from the assets, since a story and a single feed post look
  # identical from here. It wins over the carousel checks so a post switched to
  # a story is not still read as a carousel by a stale social_template name.
  def post_type
    return "story" if platform_payload&.dig("post_type") == "story"
    return "carousel" if platform_payload&.dig("carousel_asset_ids")&.size.to_i >= 2
    return "carousel" if social_template&.name&.match?(/carousel/i)
    "single"
  end

  def story?
    post_type == "story"
  end

  private

  def published_at_not_in_future
    if published_at.present? && published_at > Time.current
      errors.add(:published_at, "cannot be in the future")
    end
  end

  def scheduled_at_in_future
    if scheduled_at.present? && scheduled_at <= Time.current
      errors.add(:scheduled_at, "must be in the future")
    end
  end

  # Instagram and Facebook each have a Stories publisher; YouTube and TikTok
  # have no equivalent — without this check a post marked as a story on those
  # platforms publishes silently to the feed instead.
  def story_supported_on_platform
    return if instagram? || facebook?

    errors.add(:base, "Stories are only supported on Instagram and Facebook")
  end

  # A story is one image or video card: Meta's Stories API takes a single
  # image_url or video_url, so a carousel payload or an audio-only asset has no
  # way to publish.
  def story_requires_single_visual_asset
    if platform_payload&.dig("carousel_asset_ids").present?
      errors.add(:base, "Stories cannot be carousels — a story is a single image or video")
    end

    return if media_asset.blank?
    return if media_asset.image? || media_asset.video?

    errors.add(:media_asset, "must be an image or video — stories do not support #{media_asset.media_type}")
  end

  # Catch a story whose media Meta will reject — an over-long video, an
  # undersized frame, an oversized file — at save time. Otherwise the failure
  # arrives whenever the post is due, after the upload has already been paid
  # for: a Facebook video story reports "Resolution too low" only in the
  # processing phase, minutes after the file was fetched.
  def story_media_within_platform_limits
    return if media_asset.blank?

    StoryMediaSpec.for(platform).errors_for(media_asset).each do |message|
      errors.add(:media_asset, message)
    end
  end

  # TikTok's Content Posting API only accepts video for direct posts, so catch an
  # image here rather than letting it fail hours later when the post is published.
  def tiktok_requires_video_asset
    return if media_asset.blank?
    return if media_asset.video?

    errors.add(:media_asset, "must be a video — TikTok does not support image posts")
  end
end
