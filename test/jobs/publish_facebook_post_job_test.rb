# frozen_string_literal: true

require "test_helper"

class PublishFacebookPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:one)
    @post = planned_posts(:facebook_draft_post)
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "perform calls PagePublisher#publish with the correct planned_post" do
    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "fb_post_001", [ PlannedPost ])

    Facebook::PagePublisher.stub(:new, mock_publisher) do
      PublishFacebookPostJob.perform_now(@post.id)
    end

    assert_mock mock_publisher
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: PublishFacebookPostJob, queue: "default") do
      PublishFacebookPostJob.perform_later(@post.id)
    end
  end

  test "perform enqueues VerifyPublishedPostJob after successful publish" do
    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "fb_post_001", [ PlannedPost ])

    Facebook::PagePublisher.stub(:new, mock_publisher) do
      assert_enqueued_with(job: VerifyPublishedPostJob) do
        PublishFacebookPostJob.perform_now(@post.id)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------

  test "perform skips non-facebook posts without calling publisher" do
    ig_post = planned_posts(:draft_post)
    assert ig_post.instagram?

    Facebook::PagePublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishFacebookPostJob.perform_now(ig_post.id) }
    end
  end

  test "perform skips already-published posts without calling publisher" do
    @post.update!(status: :published)

    Facebook::PagePublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishFacebookPostJob.perform_now(@post.id) }
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
      assert_enqueued_jobs 1, only: PublishFacebookPostJob do
        Facebook::PagePublisher.stub(:new, failing_publisher(error_class, "transient")) do
          assert_nothing_raised { PublishFacebookPostJob.perform_now(@post.id) }
        end
      end

      assert_not @post.reload.failed?, "a retryable error must not fail the post on the first attempt"
    end
  end

  test "perform marks the post failed once the retries are exhausted" do
    job = PublishFacebookPostJob.new(@post.id)
    job.exception_executions = { "[Instagram::ContainerTimeoutError]" => 5 }

    Facebook::PagePublisher.stub(:new, failing_publisher(Instagram::ContainerTimeoutError, "still broken")) do
      assert_enqueued_jobs 0, only: PublishFacebookPostJob do
        assert_nothing_raised { job.perform_now }
      end
    end

    assert @post.reload.failed?
    assert_equal "still broken", @post.failure_reason
  end

  # TokenExpiredError can never succeed on a retry, so it must not match any
  # retry_on — it falls through to discard_on and fails the post at once.
  test "perform fails immediately on a TokenExpiredError without retrying" do
    assert_enqueued_jobs 0, only: PublishFacebookPostJob do
      Facebook::PagePublisher.stub(:new, failing_publisher(Instagram::TokenExpiredError, "reconnect the account")) do
        assert_nothing_raised { PublishFacebookPostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.failed?
    assert_equal "reconnect the account", @post.failure_reason
  end

  test "perform does not swallow errors from outside the Instagram namespace" do
    Facebook::PagePublisher.stub(:new, failing_publisher(ArgumentError, "boom")) do
      assert_raises(ArgumentError) { PublishFacebookPostJob.perform_now(@post.id) }
    end
  end
end
