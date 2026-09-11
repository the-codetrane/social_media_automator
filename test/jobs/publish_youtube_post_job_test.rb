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

  test "perform processes a scheduled youtube post" do
    scheduled_post = planned_posts(:due_youtube_post)
    assert scheduled_post.scheduled?

    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "yt_job_002", [ PlannedPost ])

    YouTube::VideoPublisher.stub(:new, mock_publisher) do
      PublishYouTubePostJob.perform_now(scheduled_post.id)
    end

    assert_mock mock_publisher
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
    @post.update!(status: :published)

    YouTube::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishYouTubePostJob.perform_now(@post.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Error handling
  # -------------------------------------------------------------------------

  # A publisher double whose #publish always raises the given error.
  def failing_publisher(error_class, message)
    ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise error_class, message }
      obj
    }
  end

  # Retryable errors must actually re-enqueue the job.  A re-enqueue is the only
  # observable difference between "retried" and "discarded" under perform_now,
  # so assert on enqueued_jobs rather than on the post's status.
  { "RateLimitError" => YouTube::RateLimitError,
    "ApiError" => YouTube::ApiError }.each do |name, error_class|
    test "perform retries a #{name} instead of discarding it" do
      assert_enqueued_jobs 1, only: PublishYouTubePostJob do
        YouTube::VideoPublisher.stub(:new, failing_publisher(error_class, "transient")) do
          assert_nothing_raised { PublishYouTubePostJob.perform_now(@post.id) }
        end
      end

      assert_not @post.reload.failed?, "a retryable error must not fail the post on the first attempt"
    end
  end

  test "perform marks the post failed once the retries are exhausted" do
    job = PublishYouTubePostJob.new(@post.id)
    job.exception_executions = { "[YouTube::RateLimitError]" => 5 }

    YouTube::VideoPublisher.stub(:new, failing_publisher(YouTube::RateLimitError, "still broken")) do
      assert_enqueued_jobs 0, only: PublishYouTubePostJob do
        assert_nothing_raised { job.perform_now }
      end
    end

    assert @post.reload.failed?
    assert_equal "still broken", @post.failure_reason
  end

  # UploadError can never succeed on a retry, so it must not match any
  # retry_on — it falls through to discard_on and fails the post at once.
  test "perform fails immediately on a UploadError without retrying" do
    assert_enqueued_jobs 0, only: PublishYouTubePostJob do
      YouTube::VideoPublisher.stub(:new, failing_publisher(YouTube::UploadError, "reconnect the account")) do
        assert_nothing_raised { PublishYouTubePostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.failed?
    assert_equal "reconnect the account", @post.failure_reason
  end

  test "perform does not swallow errors from outside the YouTube namespace" do
    YouTube::VideoPublisher.stub(:new, failing_publisher(ArgumentError, "boom")) do
      assert_raises(ArgumentError) { PublishYouTubePostJob.perform_now(@post.id) }
    end
  end
end
