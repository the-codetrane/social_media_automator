# frozen_string_literal: true

require "test_helper"

class DispatchScheduledPostsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues PublishInstagramPostJob for a due instagram post" do
    assert_enqueued_with(job: PublishInstagramPostJob, args: [ planned_posts(:due_instagram_post).id ]) do
      DispatchScheduledPostsJob.perform_now
    end
  end

  test "enqueues PublishFacebookPostJob for a due facebook post" do
    assert_enqueued_with(job: PublishFacebookPostJob, args: [ planned_posts(:due_facebook_post).id ]) do
      DispatchScheduledPostsJob.perform_now
    end
  end

  test "enqueues PublishYouTubePostJob for a due youtube post" do
    assert_enqueued_with(job: PublishYouTubePostJob, args: [ planned_posts(:due_youtube_post).id ]) do
      DispatchScheduledPostsJob.perform_now
    end
  end

  test "does not enqueue jobs for draft or published posts" do
    draft = planned_posts(:draft_post)
    pub   = planned_posts(:published_post)

    # Force scheduled_at into the past but leave status as draft/published
    draft.update_column(:scheduled_at, 5.minutes.ago)
    pub.update_column(:scheduled_at, 5.minutes.ago)

    enqueued_ids = []
    PublishInstagramPostJob.stub(:perform_later, ->(id) { enqueued_ids << id }) do
      PublishFacebookPostJob.stub(:perform_later, ->(id) { enqueued_ids << id }) do
        DispatchScheduledPostsJob.perform_now
      end
    end

    refute_includes enqueued_ids, draft.id
    refute_includes enqueued_ids, pub.id
  end

  test "does not dispatch future scheduled posts" do
    future_post = planned_posts(:scheduled_post)  # scheduled_at: 2 days from now
    refute future_post.scheduled_at <= Time.current

    performed_jobs = []
    PublishInstagramPostJob.stub(:perform_later, ->(id) { performed_jobs << id }) do
      PublishFacebookPostJob.stub(:perform_later, ->(id) { performed_jobs << id }) do
        DispatchScheduledPostsJob.perform_now
      end
    end

    refute_includes performed_jobs, future_post.id
  end
end
