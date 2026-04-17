# frozen_string_literal: true

require "test_helper"

class VerifyPublishedPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:one)
    @post = planned_posts(:published_post)
  end

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  test "stores permalink and verified_at in platform_payload on success" do
    permalink = "https://www.instagram.com/p/abc123/"

    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| { "permalink" => permalink, "media_type" => "IMAGE" } }
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
      obj.define_singleton_method(:verify) { |_| { "permalink" => "https://www.instagram.com/p/x/" } }
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
  # Not-found handling
  # -------------------------------------------------------------------------

  test "marks post failed when API returns code 100" do
    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| raise Instagram::ApiError.new("Does not exist", code: 100) }
      obj
    }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  test "marks post failed when API returns code 803" do
    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| raise Instagram::ApiError.new("Alias not found", code: 803) }
      obj
    }) do
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert @post.reload.failed?
  end

  test "re-raises ApiError with other codes so retry_on can handle it" do
    Instagram::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| raise Instagram::ApiError.new("Server error", code: 1) }
      obj
    }) do
      # retry_on exhausts attempts then discard_on swallows — nothing escapes perform_now
      assert_nothing_raised { VerifyPublishedPostJob.perform_now(@post.id) }
    end

    assert_not @post.reload.failed?
  end

  # -------------------------------------------------------------------------
  # Facebook dispatch
  # -------------------------------------------------------------------------

  test "uses Facebook::PostVerifier for facebook posts" do
    fb_post = planned_posts(:facebook_draft_post)
    fb_post.update!(status: :published, external_post_id: "fb_123_456")

    Facebook::PostVerifier.stub(:new, ->(_) {
      obj = Object.new
      obj.define_singleton_method(:verify) { |_| { "permalink_url" => "https://www.facebook.com/p/x" } }
      obj
    }) do
      VerifyPublishedPostJob.perform_now(fb_post.id)
    end

    assert_equal "https://www.facebook.com/p/x", fb_post.reload.platform_payload["permalink"]
  end
end
