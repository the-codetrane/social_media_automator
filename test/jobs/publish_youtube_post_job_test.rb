# frozen_string_literal: true

require "test_helper"

class PublishYouTubePostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  def setup
    @user = users(:one)
    @post = planned_posts(:youtube_draft_post)
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "perform calls VideoPublisher#publish with the correct planned_post" do
    video_id = "yt_job_001"

    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, video_id, [ PlannedPost ])

    YouTube::VideoPublisher.stub(:new, mock_publisher) do
      PublishYouTubePostJob.perform_now(@post.id)
    end

    assert_mock mock_publisher
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: PublishYouTubePostJob, queue: "default") do
      PublishYouTubePostJob.perform_later(@post.id)
    end
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------

  test "perform skips non-youtube posts without calling publisher" do
    instagram_post = planned_posts(:draft_post)
    assert instagram_post.instagram?

    YouTube::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishYouTubePostJob.perform_now(instagram_post.id) }
    end
  end

  test "perform skips already-published posts without calling publisher" do
    published_post = planned_posts(:published_post)
    assert published_post.published?

    YouTube::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishYouTubePostJob.perform_now(published_post.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Error handling / retry behaviour
  # -------------------------------------------------------------------------

  test "perform marks post failed after retries exhausted via discard_on" do
    YouTube::VideoPublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise YouTube::ApiError, "Permanent failure" }
      obj
    }) do
      assert_nothing_raised { PublishYouTubePostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  test "perform retries on RateLimitError and eventually marks failed" do
    YouTube::VideoPublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise YouTube::RateLimitError, "Quota hit" }
      obj
    }) do
      assert_nothing_raised { PublishYouTubePostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end
end
