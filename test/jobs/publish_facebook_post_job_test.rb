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
  # Error handling / retry behaviour
  # -------------------------------------------------------------------------

  test "perform marks post failed after retries exhausted via discard_on" do
    Facebook::PagePublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise Instagram::ApiError, "Permanent failure" }
      obj
    }) do
      assert_nothing_raised { PublishFacebookPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  test "perform retries on RateLimitError then marks failed after exhaustion" do
    Facebook::PagePublisher.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:publish) { |_| raise Instagram::RateLimitError, "Quota hit" }
      obj
    }) do
      assert_nothing_raised { PublishFacebookPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end
end
