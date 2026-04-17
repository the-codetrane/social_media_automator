# frozen_string_literal: true

# Publishes a single PlannedPost to a Facebook Page feed in the background.
#
# Enqueue it like this:
#   PublishFacebookPostJob.perform_later(planned_post.id)
class PublishFacebookPostJob < ApplicationJob
  queue_as :default

  retry_on Instagram::RateLimitError, wait: 1.hour,              attempts: 5
  retry_on Instagram::ApiError,       wait: :polynomially_longer, attempts: 3

  discard_on(Instagram::Error) do |job, error|
    planned_post = PlannedPost.find_by(id: job.arguments.first)
    planned_post&.update(status: :failed)
    Rails.logger.error("[PublishFacebookPostJob] Permanently failed for PlannedPost##{job.arguments.first}: #{error.message}")
  end

  # @param planned_post_id [Integer]
  def perform(planned_post_id)
    planned_post = PlannedPost.find(planned_post_id)

    unless planned_post.facebook?
      Rails.logger.warn("[PublishFacebookPostJob] PlannedPost##{planned_post_id} is not a Facebook post, skipping.")
      return
    end

    unless planned_post.scheduled? || planned_post.draft?
      Rails.logger.warn("[PublishFacebookPostJob] PlannedPost##{planned_post_id} has status '#{planned_post.status}', skipping.")
      return
    end

    publisher = Facebook::PagePublisher.new(planned_post.user)
    post_id   = publisher.publish(planned_post)

    Rails.logger.info("[PublishFacebookPostJob] Published PlannedPost##{planned_post_id} → post_id=#{post_id}")
  end
end
