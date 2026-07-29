# frozen_string_literal: true

# Publishes a single PlannedPost to TikTok in the background.
#
# Enqueue it like this:
#   PublishTikTokPostJob.perform_later(planned_post.id)
#
# Or schedule it for a specific time:
#   PublishTikTokPostJob.set(wait_until: planned_post.scheduled_at)
#                       .perform_later(planned_post.id)
#
# Retries:
# - TikTok::RateLimitError      → retried after 1 hour (daily post quota)
# - TikTok::PublishTimeoutError → retried after 30 s (processing/moderation lag)
# - TikTok::UploadError         → retried 3× with exponential back-off
# - Other TikTok::Error         → retried 3× then marked failed
#
# TikTok::PermanentError is deliberately absent from the retry list: an
# unverified domain, a privacy level the creator cannot use or an unaudited
# client will never succeed on a retry, so those go straight to failed.
class PublishTikTokPostJob < ApplicationJob
  queue_as :default

  # Marks the post failed, whether that is because retries ran out or because
  # the error was never retryable in the first place.
  # PlannedPost#mark_failed! stores the reason on the record so the UI can show
  # why, and skips validation — a TikTok post whose asset is not a video fails
  # its own validation, so update! would raise and update would silently no-op.
  MARK_FAILED = proc do |job, error|
    PlannedPost.find_by(id: job.arguments.first)&.mark_failed!(error.message)
    Rails.logger.error("[PublishTikTokPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  # Declaration order matters: retry_on and discard_on both register rescue_from
  # handlers, and those are matched last-registered-first.  The catch-all
  # discard_on therefore has to come FIRST, so the specific retry_on rules below
  # it win for the errors they name and only unmatched errors — notably
  # PermanentError — fall through to be discarded immediately.
  discard_on TikTok::Error, &MARK_FAILED

  retry_on TikTok::PublishTimeoutError, wait: 30.seconds, attempts: 5, &MARK_FAILED
  retry_on TikTok::RateLimitError,      wait: 1.hour,     attempts: 5, &MARK_FAILED
  retry_on TikTok::UploadError,         wait: :polynomially_longer, attempts: 3, &MARK_FAILED
  retry_on TikTok::ApiError,            wait: :polynomially_longer, attempts: 3, &MARK_FAILED

  # @param planned_post_id [Integer]
  def perform(planned_post_id)
    planned_post = PlannedPost.find(planned_post_id)

    unless planned_post.tiktok?
      Rails.logger.warn("[PublishTikTokPostJob] PlannedPost##{planned_post_id} is not a TikTok post, skipping.")
      return
    end

    unless planned_post.scheduled? || planned_post.draft?
      Rails.logger.warn("[PublishTikTokPostJob] PlannedPost##{planned_post_id} has status '#{planned_post.status}', skipping.")
      return
    end

    publisher  = TikTok::VideoPublisher.new(planned_post.user)
    publish_id = publisher.publish(planned_post)
    Rails.logger.info("[PublishTikTokPostJob] Published PlannedPost##{planned_post_id} → publish_id=#{publish_id}")
  end
end
