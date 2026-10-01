# frozen_string_literal: true

require "test_helper"

class PublishInstagramPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  def setup
    @user = users(:one)
    @post = planned_posts(:draft_post)
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "perform calls MediaPublisher#publish with the correct planned_post" do
    published_id = "ig_media_job_001"

    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, published_id, [ PlannedPost ])

    Instagram::MediaPublisher.stub(:new, mock_publisher) do
      PublishInstagramPostJob.perform_now(@post.id)
    end

    assert_mock mock_publisher
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: PublishInstagramPostJob, queue: "default") do
      PublishInstagramPostJob.perform_later(@post.id)
    end
  end

  test "perform enqueues VerifyPublishedPostJob after successful publish" do
    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "ig_media_001", [ PlannedPost ])

    Instagram::MediaPublisher.stub(:new, mock_publisher) do
      assert_enqueued_with(job: VerifyPublishedPostJob) do
        PublishInstagramPostJob.perform_now(@post.id)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------

  test "perform skips non-instagram posts without calling publisher" do
    youtube_post = planned_posts(:scheduled_post)  # platform: youtube
    assert youtube_post.youtube?

    Instagram::MediaPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishInstagramPostJob.perform_now(youtube_post.id) }
    end
  end

  # This guard is why the Instagram publishers must not mark a post failed
  # before re-raising: doing so flipped the status on the first attempt, so
  # every retry landed here and returned without republishing, leaving the
  # retry_on rules below inert.  See the FAILURE_IS_THE_JOBS_JOB assertions in
  # test/services/instagram/*_publisher_test.rb for the other half.
  test "perform skips an already-failed post without calling publisher" do
    draft_post = planned_posts(:draft_post)
    draft_post.mark_failed!("earlier attempt blew up")

    Instagram::MediaPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishInstagramPostJob.perform_now(draft_post.id) }
    end
  end

  test "perform skips already-published posts without calling publisher" do
    published_post = planned_posts(:published_post)
    assert published_post.published?

    Instagram::MediaPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishInstagramPostJob.perform_now(published_post.id) }
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
  { "ContainerTimeoutError" => Instagram::ContainerTimeoutError,
    "RateLimitError" => Instagram::RateLimitError,
    "ApiError" => Instagram::ApiError }.each do |name, error_class|
    test "perform retries a #{name} instead of discarding it" do
      assert_enqueued_jobs 1, only: PublishInstagramPostJob do
        Instagram::MediaPublisher.stub(:new, failing_publisher(error_class, "transient")) do
          assert_nothing_raised { PublishInstagramPostJob.perform_now(@post.id) }
        end
      end

      assert_not @post.reload.failed?, "a retryable error must not fail the post on the first attempt"
    end
  end

  test "perform marks the post failed once the retries are exhausted" do
    job = PublishInstagramPostJob.new(@post.id)
    job.exception_executions = { "[Instagram::ContainerTimeoutError]" => 5 }

    Instagram::MediaPublisher.stub(:new, failing_publisher(Instagram::ContainerTimeoutError, "still broken")) do
      assert_enqueued_jobs 0, only: PublishInstagramPostJob do
        assert_nothing_raised { job.perform_now }
      end
    end

    assert @post.reload.failed?
    assert_equal "still broken", @post.failure_reason
  end

  # TokenExpiredError can never succeed on a retry, so it must not match any
  # retry_on — it falls through to discard_on and fails the post at once.
  test "perform fails immediately on a TokenExpiredError without retrying" do
    assert_enqueued_jobs 0, only: PublishInstagramPostJob do
      Instagram::MediaPublisher.stub(:new, failing_publisher(Instagram::TokenExpiredError, "reconnect the account")) do
        assert_nothing_raised { PublishInstagramPostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.failed?
    assert_equal "reconnect the account", @post.failure_reason
  end

  test "perform does not swallow errors from outside the Instagram namespace" do
    Instagram::MediaPublisher.stub(:new, failing_publisher(ArgumentError, "boom")) do
      assert_raises(ArgumentError) { PublishInstagramPostJob.perform_now(@post.id) }
    end
  end
end
