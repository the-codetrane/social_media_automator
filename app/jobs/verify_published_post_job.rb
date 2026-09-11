# frozen_string_literal: true

# Verifies that a published PlannedPost is live on its platform by fetching
# it from the API and storing the permalink + metadata in platform_payload.
#
# Enqueued automatically 2 minutes after a successful publish, and can be
# triggered manually via the show page re-verify button.
#
# If the platform returns a "post not found" error (Meta codes 100 / 803),
# the post is marked failed. Other API errors are retried normally.
#
# Stories are read differently on both platforms — see #fetch_from_platform —
# and are never marked failed by verification: a story is gone from the API
# after 24 hours by design, which says nothing about whether it published.
#
# Retries:
# - Instagram::ApiError  → retried 3× with exponential back-off
# - Other Instagram::Error → given up on at once
#
# Giving up is only ever logged: a post that published fine but could not be
# read back is still published, so the record is left alone. RateLimitError and
# TokenExpiredError fall through to that — a permalink is a convenience, not
# worth holding a job for an hour or until the account is reconnected.
class VerifyPublishedPostJob < ApplicationJob
  queue_as :default

  # Verification failing says nothing about the post, so this only logs — unlike
  # the publish jobs, it must not touch the record's status.
  GIVE_UP = proc do |job, error|
    Rails.logger.error("[VerifyPublishedPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  # Declaration order matters: retry_on and discard_on both register rescue_from
  # handlers, and those are matched last-registered-first.  The catch-all
  # discard_on therefore has to come FIRST, so the retry_on below it wins for the
  # error it names and everything else falls through to be discarded at once.
  discard_on Instagram::Error, &GIVE_UP

  retry_on Instagram::ApiError, wait: :polynomially_longer, attempts: 3, &GIVE_UP

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
      platform_payload: planned_post.platform_payload.to_h.merge(verification_data(result))
    )

    Rails.logger.info("[VerifyPublishedPostJob] Verified PlannedPost##{planned_post_id}")
  rescue Instagram::ApiError => e
    raise unless NOT_FOUND_CODES.include?(e.code.to_i)

    planned_post = PlannedPost.find_by(id: planned_post_id)

    # A story is expected to disappear once its 24 hours are up, so "not found"
    # is not evidence that it failed to publish. Feed posts are marked failed.
    if planned_post&.story?
      Rails.logger.info("[VerifyPublishedPostJob] Story for PlannedPost##{planned_post_id} is no longer on the platform: #{e.message}")
    else
      planned_post&.update(status: :failed)
      Rails.logger.error("[VerifyPublishedPostJob] Post not found on platform for PlannedPost##{planned_post_id}: #{e.message}")
    end
  end

  private

  # Instagram reads a story as an ordinary media object with a narrower field
  # list; Facebook cannot read one as a post at all and has to list the Page's
  # stories instead.
  def fetch_from_platform(planned_post)
    case planned_post.platform
    when "instagram"
      Instagram::PostVerifier.new(planned_post.user)
        .verify(planned_post.external_post_id, story: planned_post.story?)
    when "facebook"
      verifier = Facebook::PostVerifier.new(planned_post.user)

      if planned_post.story?
        verifier.verify_story(planned_post.external_post_id)
      else
        verifier.verify(planned_post.external_post_id)
      end
    else
      raise Instagram::ApiError, "Verification not supported for platform '#{planned_post.platform}'"
    end
  end

  # The three response shapes name the permalink differently: "permalink" on an
  # IG media object, "permalink_url" on a Page post, "url" on a Page story.
  def verification_data(result)
    {
      "permalink" => result["permalink"] || result["permalink_url"] || result["url"],
      # Instagram only: MUSIC when a catalogue track is attached to the Reel,
      # ORIGINAL_SOUND otherwise. Absent for non-video and non-Instagram posts.
      "media_audio_type" => result["media_audio_type"],
      # Instagram only: AD, FEED, STORY or REELS.
      "media_product_type" => result["media_product_type"],
      # Facebook stories only: PUBLISHED, ARCHIVED, or the verifier's UNLISTED.
      "story_status" => result["status"],
      "verified_at"  => Time.current.iso8601
    }.compact
  end
end
