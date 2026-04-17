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

  test "perform skips already-published posts without calling publisher" do
    published_post = planned_posts(:published_post)
    assert published_post.published?

    Instagram::MediaPublisher.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { PublishInstagramPostJob.perform_now(published_post.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Error handling / retry behaviour
  # -------------------------------------------------------------------------

  test "perform marks post failed after retries exhausted via discard_on" do
    Instagram::MediaPublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise Instagram::ApiError, "Permanent failure" }
      obj
    }) do
      # discard_on swallows the error — nothing escapes perform_now
      assert_nothing_raised do
        PublishInstagramPostJob.perform_now(@post.id)
      end
    end

    # The discard_on block updates the post status to :failed
    assert @post.reload.failed?
  end

  test "perform retries on RateLimitError (solid_queue handles re-enqueue)" do
    Instagram::MediaPublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise Instagram::RateLimitError, "Quota hit" }
      obj
    }) do
      # retry_on exhausts attempts then discard_on swallows — nothing escapes
      assert_nothing_raised do
        PublishInstagramPostJob.perform_now(@post.id)
      end
    end

    assert @post.reload.failed?
  end
end
