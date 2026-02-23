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
# - Instagram::RateLimitError → retried after a 1-hour wait (quota resets rolling 24 h)
# - Instagram::ContainerTimeoutError → retried after 30 s (video processing lag)
# - Other Instagram::Error → retried 3× with exponential back-off then marked failed
class PublishInstagramPostJob < ApplicationJob
  queue_as :default

  # Retry transient errors a limited number of times.
  retry_on Instagram::ContainerTimeoutError, wait: 30.seconds, attempts: 5
  retry_on Instagram::RateLimitError,        wait: 1.hour,     attempts: 5
  retry_on Instagram::ApiError,              wait: :polynomially_longer, attempts: 3

  # After all retries are exhausted, mark the post as failed and re-raise.
  discard_on(Instagram::Error) do |job, error|
    planned_post = PlannedPost.find_by(id: job.arguments.first)
    planned_post&.update(status: :failed)
    Rails.logger.error("[PublishInstagramPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

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

    Rails.logger.info("[PublishInstagramPostJob] Published PlannedPost##{planned_post_id} → ig_media_id=#{ig_media_id}")
  end
end
