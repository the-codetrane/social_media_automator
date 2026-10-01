# frozen_string_literal: true

require "test_helper"

class PublishTikTokPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # -------------------------------------------------------------------------
  # Setup
  # -------------------------------------------------------------------------

  def setup
    @user = users(:one)
    @post = planned_posts(:tiktok_draft_post)
  end

  # A publisher double whose #publish always raises the given error.
  def failing_publisher(error_class, message)
    ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise error_class, message }
      obj
    }
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "perform calls VideoPublisher#publish with the correct planned_post" do
    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "v_pub_file~v2.001", [ PlannedPost ])

    TikTok::VideoPublisher.stub(:new, mock_publisher) do
      PublishTikTokPostJob.perform_now(@post.id)
    end

    assert_mock mock_publisher
  end

  test "perform enqueues on the default queue" do
    assert_enqueued_with(job: PublishTikTokPostJob, queue: "default") do
      PublishTikTokPostJob.perform_later(@post.id)
    end
  end

  test "perform processes a scheduled tiktok post" do
    scheduled_post = planned_posts(:due_tiktok_post)
    assert scheduled_post.scheduled?

    mock_publisher = Minitest::Mock.new
    mock_publisher.expect(:publish, "v_pub_file~v2.002", [ PlannedPost ])

    TikTok::VideoPublisher.stub(:new, mock_publisher) do
      PublishTikTokPostJob.perform_now(scheduled_post.id)
    end

    assert_mock mock_publisher
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------

  test "perform skips non-tiktok posts without calling publisher" do
    instagram_post = planned_posts(:draft_post)
    assert instagram_post.instagram?

    TikTok::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishTikTokPostJob.perform_now(instagram_post.id) }
    end
  end

  test "perform skips already-published posts without calling publisher" do
    @post.update!(status: :published)

    TikTok::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishTikTokPostJob.perform_now(@post.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Error handling
  # -------------------------------------------------------------------------

  # Retryable errors must actually re-enqueue the job.  A re-enqueue is the
  # only observable difference between "retried" and "discarded" under
  # perform_now, so assert on enqueued_jobs rather than on the post's status.
  { "RateLimitError"      => TikTok::RateLimitError,
    "PublishTimeoutError" => TikTok::PublishTimeoutError,
    "UploadError"         => TikTok::UploadError,
    "ApiError"            => TikTok::ApiError }.each do |name, error_class|
    test "perform retries a #{name} instead of discarding it" do
      assert_enqueued_jobs 1, only: PublishTikTokPostJob do
        TikTok::VideoPublisher.stub(:new, failing_publisher(error_class, "transient")) do
          assert_nothing_raised { PublishTikTokPostJob.perform_now(@post.id) }
        end
      end

      assert_not @post.reload.failed?, "a retryable error must not fail the post on the first attempt"
    end
  end

  # This guard is why TikTok::VideoPublisher must not mark a post failed before
  # re-raising: doing so flipped the status on the first attempt, so every
  # retry landed here and returned without republishing, leaving the retry_on
  # rules below inert.  See the FAILURE_IS_THE_JOBS_JOB assertions in
  # test/services/tiktok/video_publisher_test.rb for the other half.
  test "perform skips an already-failed post without calling publisher" do
    @post.mark_failed!("earlier attempt blew up")

    TikTok::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishTikTokPostJob.perform_now(@post.id) }
    end
  end

  test "perform marks the post failed once the retries are exhausted" do
    job = PublishTikTokPostJob.new(@post.id)
    job.exception_executions = { "[TikTok::ApiError]" => 3 }

    TikTok::VideoPublisher.stub(:new, failing_publisher(TikTok::ApiError, "still broken")) do
      assert_enqueued_jobs 0, only: PublishTikTokPostJob do
        assert_nothing_raised { job.perform_now }
      end
    end

    assert @post.reload.failed?
  end

  # A PermanentError can never succeed on retry, so it must not match any
  # retry_on — it falls through to discard_on and fails the post at once.
  test "perform fails immediately on a PermanentError without retrying" do
    error = TikTok::PermanentError.new("domain not verified", code: "url_ownership_unverified")

    assert_enqueued_jobs 0, only: PublishTikTokPostJob do
      TikTok::VideoPublisher.stub(:new, ->(_) {
        obj = Object.new
        obj.define_singleton_method(:publish) { |_| raise error }
        obj
      }) do
        assert_nothing_raised { PublishTikTokPostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.failed?
  end

  # A TikTok post pointing at an image fails its own model validation, so a
  # plain update(status: :failed) would silently no-op and strand the post.
  test "perform still marks an invalid post failed" do
    @post.update_column(:media_asset_id, media_assets(:sample_image).id)
    assert_not @post.reload.valid?

    TikTok::VideoPublisher.stub(:new, failing_publisher(TikTok::PermanentError, "not a video")) do
      assert_nothing_raised { PublishTikTokPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?, "an invalid post must still be recorded as failed"
  end

  test "perform does not swallow errors from outside the TikTok namespace" do
    TikTok::VideoPublisher.stub(:new, failing_publisher(ArgumentError, "not a video")) do
      assert_raises(ArgumentError) { PublishTikTokPostJob.perform_now(@post.id) }
    end
  end
end
