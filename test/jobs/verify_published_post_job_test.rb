# frozen_string_literal: true

require "test_helper"

class VerifyPublishedPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:one)
    @post = planned_posts(:published_post)
  end

  # A published Facebook story, as StoriesPublisher would have left it.
  def facebook_story
    planned_posts(:facebook_draft_post).tap do |post|
      post.update!(
        status:           :published,
        external_post_id: "fb_story_001",
        published_at:     Time.current,
        platform_payload: { "post_type" => "story", "media_type" => "STORY" }
      )
    end
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "stores permalink and verified_at in platform_payload on success" do
    permalink = "https://www.instagram.com/p/abc123/"

    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| { "permalink" => permalink, "media_type" => "IMAGE" } }
      obj
    }) do
      VerifyPublishedPostJob.perform_now(@post.id)
    end

    payload = @post.reload.platform_payload
    assert_equal permalink, payload["permalink"]
    assert payload["verified_at"].present?
  end

  test "merges into existing platform_payload without losing prior data" do
    @post.update!(platform_payload: { "ig_media_id" => "prior_id" })

    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| { "permalink" => "https://www.instagram.com/p/x/" } }
      obj
    }) do
      VerifyPublishedPostJob.perform_now(@post.id)
    end

    payload = @post.reload.platform_payload
    assert_equal "prior_id", payload["ig_media_id"]
    assert payload["permalink"].present?
  end

  test "enqueues on the default queue" do
    assert_enqueued_with(job: VerifyPublishedPostJob, queue: "default") do
      VerifyPublishedPostJob.perform_later(@post.id)
    end
  end

  # -------------------------------------------------------------------------
  # Guard clauses
  # -------------------------------------------------------------------------

  test "skips posts that are not published" do
    draft = planned_posts(:draft_post)

    Instagram::PostVerifier.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(draft.id) }
    end
  end

  test "skips published posts with no external_post_id" do
    @post.update!(external_post_id: nil)

    Instagram::PostVerifier.stub(:new, ->(_) { raise "should not be called" }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end
  end

  # -------------------------------------------------------------------------
  # Stories
  # -------------------------------------------------------------------------

  test "verifies an instagram story with the story-safe field list" do
    @post.update!(platform_payload: { "post_type" => "story" })
    seen = nil

    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) do |_, story: false|
        seen = story
        { "permalink" => "https://www.instagram.com/stories/x/", "media_product_type" => "STORY" }
      end
      obj
    }) do
      VerifyPublishedPostJob.perform_now(@post.id)
    end

    assert seen, "verify should have been told this is a story"
    payload = @post.reload.platform_payload
    assert_equal "https://www.instagram.com/stories/x/", payload["permalink"]
    assert_equal "STORY", payload["media_product_type"]
    assert @post.published?
  end

  test "verifies a facebook story by listing the page's stories" do
    story = facebook_story

    Facebook::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| raise "a story is not readable as a post" }
      obj.define_singleton_method(:verify_story) do |post_id|
        { "post_id" => post_id, "status" => "PUBLISHED", "url" => "https://www.facebook.com/stories/1/" }
      end
      obj
    }) do
      VerifyPublishedPostJob.perform_now(story.id)
    end

    payload = story.reload.platform_payload
    assert_equal "https://www.facebook.com/stories/1/", payload["permalink"]
    assert_equal "PUBLISHED", payload["story_status"]
  end

  test "records an unlisted facebook story without failing it" do
    story = facebook_story

    Facebook::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify_story) { |_| { "status" => "UNLISTED" } }
      obj
    }) do
      VerifyPublishedPostJob.perform_now(story.id)
    end

    story.reload
    assert story.published?, "an expired story is not a publishing failure"
    assert_equal "UNLISTED", story.platform_payload["story_status"]
    assert_nil story.platform_payload["permalink"]
  end

  # A story is gone from the API after 24 hours by design, so a not-found says
  # nothing about whether it published.
  test "does not mark a story failed when the API returns code 100" do
    @post.update!(platform_payload: { "post_type" => "story" })

    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Does not exist", code: 100) }
      obj
    }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert @post.reload.published?
  end

  # -------------------------------------------------------------------------
  # Not-found handling
  # -------------------------------------------------------------------------

  test "marks post failed when API returns code 100" do
    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Does not exist", code: 100) }
      obj
    }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  test "marks post failed when API returns code 803" do
    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Alias not found", code: 803) }
      obj
    }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  # A re-enqueue is the only observable difference between "retried" and
  # "discarded" under perform_now, so assert on enqueued_jobs — asserting the
  # post is still unfailed passes either way and proves nothing.
  test "retries an ApiError with any other code instead of discarding it" do
    assert_enqueued_jobs 1, only: VerifyPublishedPostJob do
      Instagram::PostVerifier.stub(:new, ->(_) {
        obj = Object.new
        obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Server error", code: 1) }
        obj
      }) do
        assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
      end
    end

    assert_not @post.reload.failed?
  end

  test "gives up once the retries are exhausted, leaving the post published" do
    job = VerifyPublishedPostJob.new(@post.id)
    job.exception_executions = { "[Instagram::ApiError]" => 3 }

    assert_enqueued_jobs 0, only: VerifyPublishedPostJob do
      Instagram::PostVerifier.stub(:new, ->(_) {
        obj = Object.new
        obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Server error", code: 1) }
        obj
      }) do
        assert_nothing_raised { job.perform_now }
      end
    end

    # Verification failing says nothing about the post — it stays published.
    assert @post.reload.published?
  end

  # RateLimitError does not subclass ApiError, so it falls through to discard_on
  # rather than holding a job for an hour over a permalink.
  test "gives up at once on an error outside the retryable class" do
    assert_enqueued_jobs 0, only: VerifyPublishedPostJob do
      Instagram::PostVerifier.stub(:new, ->(_) {
        obj = Object.new
        obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::RateLimitError.new("Quota hit", code: 4) }
        obj
      }) do
        assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.published?
  end

  test "a not-found is handled inline and never retried" do
    assert_enqueued_jobs 0, only: VerifyPublishedPostJob do
      Instagram::PostVerifier.stub(:new, ->(_) {
        obj = Object.new
        obj.define_singleton_method(:verify) { |_, **_opts| raise Instagram::ApiError.new("Does not exist", code: 100) }
        obj
      }) do
        assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
      end
    end

    assert @post.reload.failed?
  end

  # -------------------------------------------------------------------------
  # Facebook dispatch
  # -------------------------------------------------------------------------

  test "uses Facebook::PostVerifier for facebook posts" do
    fb_post = planned_posts(:facebook_draft_post)
    fb_post.update!(status: :published, external_post_id: "fb_123_456")

    Facebook::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_, **_opts| { "permalink_url" => "https://www.facebook.com/p/x" } }
      obj
    }) do
      VerifyPublishedPostJob.perform_now(fb_post.id)
    end

    assert_equal "https://www.facebook.com/p/x", fb_post.reload.platform_payload["permalink"]
  end
end
