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
# - Other YouTube::Error    → retried 3× with exponential back-off then marked failed
class PublishYouTubePostJob < ApplicationJob
  queue_as :default

  retry_on YouTube::RateLimitError, wait: 1.hour,              attempts: 5
  retry_on YouTube::ApiError,       wait: :polynomially_longer, attempts: 3

  discard_on(YouTube::Error) do |job, error|
    planned_post = PlannedPost.find_by(id: job.arguments.first)
    planned_post&.update(status: :failed)
    Rails.logger.error("[PublishYouTubePostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

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
