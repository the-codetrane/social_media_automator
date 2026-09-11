# frozen_string_literal: true

# Publishes a single PlannedPost to Instagram in the background.
#
# Enqueue it like this:
#   PublishInstagramPostJob.perform_later(planned_post.id)
#
# Or schedule it for a specific time:
#   PublishInstagramPostJob.set(wait_until: planned_post.scheduled_at)
#                         .perform_later(planned_post.id)
#
# Retries:
# - Instagram::ContainerTimeoutError → retried after 30 s (video processing lag)
# - Instagram::RateLimitError        → retried after 1 hour (quota resets rolling 24 h)
# - Instagram::ApiError              → retried 3× with exponential back-off
# - Other Instagram::Error           → marked failed at once
#
# Instagram::TokenExpiredError is deliberately absent from the retry list: a
# token that has expired will not have un-expired 30 seconds later, so it goes
# straight to failed and the account needs reconnecting.
class PublishInstagramPostJob < ApplicationJob
  queue_as :default

  # Marks the post failed, whether that is because retries ran out or because
  # the error was never retryable in the first place.
  # PlannedPost#mark_failed! stores the reason on the record so the UI can show
  # why, and skips validation — a post can be invalid for the very reason it
  # failed, in which case update! would raise and update would silently no-op.
  MARK_FAILED = proc do |job, error|
    PlannedPost.find_by(id: job.arguments.first)&.mark_failed!(error.message)
    Rails.logger.error("[PublishInstagramPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  # Declaration order matters: retry_on and discard_on both register rescue_from
  # handlers, and those are matched last-registered-first.  The catch-all
  # discard_on therefore has to come FIRST, so the specific retry_on rules below
  # it win for the errors they name and only unmatched errors — notably
  # TokenExpiredError — fall through to be discarded immediately.
  discard_on Instagram::Error, &MARK_FAILED

  retry_on Instagram::ContainerTimeoutError, wait: 30.seconds, attempts: 5, &MARK_FAILED
  retry_on Instagram::RateLimitError,        wait: 1.hour,     attempts: 5, &MARK_FAILED
  retry_on Instagram::ApiError,              wait: :polynomially_longer, attempts: 3, &MARK_FAILED

  # @param planned_post_id [Integer]
  def perform(planned_post_id)
    planned_post = PlannedPost.find(planned_post_id)

    unless planned_post.instagram?
      Rails.logger.warn("[PublishInstagramPostJob] PlannedPost##{planned_post_id} is not an Instagram post, skipping.")
      return
    end

    unless planned_post.scheduled? || planned_post.draft?
      Rails.logger.warn("[PublishInstagramPostJob] PlannedPost##{planned_post_id} has status '#{planned_post.status}', skipping.")
      return
    end

    publisher = Instagram::MediaPublisher.new(planned_post.user)
    ig_media_id = publisher.publish(planned_post)

    VerifyPublishedPostJob.set(wait: 2.minutes).perform_later(planned_post_id)
    Rails.logger.info("[PublishInstagramPostJob] Published PlannedPost##{planned_post_id} → ig_media_id=#{ig_media_id}")
  end
end
