# frozen_string_literal: true

# Publishes a single PlannedPost to YouTube in the background.
#
# Enqueue it like this:
#   PublishYouTubePostJob.perform_later(planned_post.id)
#
# Or schedule it for a specific time:
#   PublishYouTubePostJob.set(wait_until: planned_post.scheduled_at)
#                        .perform_later(planned_post.id)
#
# Retries:
# - YouTube::RateLimitError → retried after 1 hour (daily quota resets at midnight PT)
# - YouTube::ApiError       → retried 3× with exponential back-off
# - Other YouTube::Error    → marked failed at once
#
# YouTube::TokenExpiredError and YouTube::UploadError are deliberately absent
# from the retry list. An expired token will not have un-expired 30 seconds
# later; a failed transfer needs the upload restarted rather than the job
# re-run, so both go straight to failed.
class PublishYouTubePostJob < ApplicationJob
  queue_as :default

  # Marks the post failed, whether that is because retries ran out or because
  # the error was never retryable in the first place.
  # PlannedPost#mark_failed! stores the reason on the record so the UI can show
  # why, and skips validation — a post can be invalid for the very reason it
  # failed, in which case update! would raise and update would silently no-op.
  MARK_FAILED = proc do |job, error|
    PlannedPost.find_by(id: job.arguments.first)&.mark_failed!(error.message)
    Rails.logger.error("[PublishYouTubePostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  # Declaration order matters: retry_on and discard_on both register rescue_from
  # handlers, and those are matched last-registered-first.  The catch-all
  # discard_on therefore has to come FIRST, so the specific retry_on rules below
  # it win for the errors they name and only unmatched errors — notably
  # TokenExpiredError and UploadError — fall through to be discarded immediately.
  discard_on YouTube::Error, &MARK_FAILED

  retry_on YouTube::RateLimitError, wait: 1.hour,              attempts: 5, &MARK_FAILED
  retry_on YouTube::ApiError,       wait: :polynomially_longer, attempts: 3, &MARK_FAILED

  # @param planned_post_id [Integer]
  def perform(planned_post_id)
    planned_post = PlannedPost.find(planned_post_id)

    unless planned_post.youtube?
      Rails.logger.warn("[PublishYouTubePostJob] PlannedPost##{planned_post_id} is not a YouTube post, skipping.")
      return
    end

    unless planned_post.scheduled? || planned_post.draft?
      Rails.logger.warn("[PublishYouTubePostJob] PlannedPost##{planned_post_id} has status '#{planned_post.status}', skipping.")
      return
    end

    publisher = YouTube::VideoPublisher.new(planned_post.user)
    video_id  = publisher.publish(planned_post)
    Rails.logger.info("[PublishYouTubePostJob] Published PlannedPost##{planned_post_id} → youtube_video_id=#{video_id}")
  end
end
