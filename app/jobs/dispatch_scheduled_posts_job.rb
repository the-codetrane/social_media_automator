# frozen_string_literal: true

# Dispatches publish jobs for any PlannedPost that is due.
# Runs every minute via Solid Queue recurring tasks (config/recurring.yml).
#
# Each platform job re-checks status before publishing, so occasional
# double-enqueues (e.g. slow job + next minute tick) are safe.
class DispatchScheduledPostsJob < ApplicationJob
  queue_as :default

  def perform
    PlannedPost.where(status: :scheduled)
               .where(scheduled_at: ..Time.current)
               .find_each do |post|
      case post.platform
      when "instagram"
        PublishInstagramPostJob.perform_later(post.id)
      when "facebook"
        PublishFacebookPostJob.perform_later(post.id)
      else
        Rails.logger.warn("[DispatchScheduledPostsJob] No publisher for platform '#{post.platform}' on PlannedPost##{post.id}")
      end
    end
  end
end
