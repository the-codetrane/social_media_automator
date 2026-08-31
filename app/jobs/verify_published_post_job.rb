# frozen_string_literal: true

# Verifies that a published PlannedPost is live on its platform by fetching
# it from the API and storing the permalink + metadata in platform_payload.
#
# Enqueued automatically 2 minutes after a successful publish, and can be
# triggered manually via the show page re-verify button.
#
# If the platform returns a "post not found" error (Meta codes 100 / 803),
# the post is marked failed. Other API errors are retried normally.
class VerifyPublishedPostJob < ApplicationJob
  queue_as :default

  retry_on Instagram::ApiError, wait: :polynomially_longer, attempts: 3

  discard_on(Instagram::Error) do |job, error|
    Rails.logger.error("[VerifyPublishedPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  NOT_FOUND_CODES = [ 100, 803 ].freeze

  # @param planned_post_id [Integer]
  def perform(planned_post_id)
    planned_post = PlannedPost.find(planned_post_id)

    unless planned_post.published? && planned_post.external_post_id.present?
      Rails.logger.warn("[VerifyPublishedPostJob] PlannedPost##{planned_post_id} is not published or has no external_post_id, skipping.")
      return
    end

    result = fetch_from_platform(planned_post)

    planned_post.update!(
      platform_payload: planned_post.platform_payload.to_h.merge(verification_data(planned_post.platform, result))
    )

    Rails.logger.info("[VerifyPublishedPostJob] Verified PlannedPost##{planned_post_id}")
  rescue Instagram::ApiError => e
    if NOT_FOUND_CODES.include?(e.code.to_i)
      planned_post = PlannedPost.find_by(id: planned_post_id)
      planned_post&.update(status: :failed)
      Rails.logger.error("[VerifyPublishedPostJob] Post not found on platform for PlannedPost##{planned_post_id}: #{e.message}")
    else
      raise
    end
  end

  private

  def fetch_from_platform(planned_post)
    case planned_post.platform
    when "instagram"
      Instagram::PostVerifier.new(planned_post.user).verify(planned_post.external_post_id)
    when "facebook"
      Facebook::PostVerifier.new(planned_post.user).verify(planned_post.external_post_id)
    else
      raise Instagram::ApiError, "Verification not supported for platform '#{planned_post.platform}'"
    end
  end

  def verification_data(platform, result)
    permalink = result["permalink"] || result["permalink_url"]
    {
      "permalink" => permalink,
      # Instagram only: MUSIC when a catalogue track is attached to the Reel,
      # ORIGINAL_SOUND otherwise. Absent for non-video and non-Instagram posts.
      "media_audio_type" => result["media_audio_type"],
      "verified_at"      => Time.current.iso8601
    }.compact
  end
end
