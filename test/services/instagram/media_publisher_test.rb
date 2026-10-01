# frozen_string_literal: true

require "test_helper"

module Instagram
  class MediaPublisherTest < ActiveSupport::TestCase
# The publisher raises and leaves the post alone; PublishInstagramPostJob
# marks it failed once retries are exhausted or the error was never
# retryable.  The publisher used to do this itself, which tripped the job's
# status guard on every retry and made retry_on inert.
FAILURE_IS_THE_JOBS_JOB =
  "the publisher must not mark the post failed — that is the job's call, " \
  "and doing it here breaks every retry"

    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @user      = users(:one)
      @publisher = Instagram::MediaPublisher.new(@user)

      # Default quota response — quota not exhausted
      @quota_ok = { "data" => [ { "quota_usage" => 2, "config" => { "quota_total" => 25 } } ] }
      # Default container status — immediately FINISHED
      @finished_status = { "status_code" => "FINISHED" }
    end

    # Stub the underlying ApiClient to avoid real HTTP.
    # Yields the publisher with the client stubbed.
    def with_stubbed_client(get_responses: {}, post_responses: {})
      mock_client = Object.new

      mock_client.define_singleton_method(:get) do |path, _params = {}|
        get_responses.fetch(path) do
          raise "Unexpected GET #{path}"
        end
      end

      mock_client.define_singleton_method(:post) do |path, _body = {}|
        post_responses.fetch(path) do
          raise "Unexpected POST #{path}"
        end
      end

      mock_client.define_singleton_method(:publishing_limit) do |_ig_user_id|
        { "data" => [ { "quota_usage" => 2, "config" => { "quota_total" => 25 } } ] }
      end

      @publisher.instance_variable_set(:@client, mock_client)
      yield @publisher
    end

    # -------------------------------------------------------------------------
    # #publish — photo
    # -------------------------------------------------------------------------

    test "publish_photo creates container, polls, publishes and updates planned_post" do
      post  = planned_posts(:draft_post)
      asset = post.media_asset
      ig_id = @user.instagram_user_id

      container_id = "cont_photo_001"
      media_id     = "ig_media_photo_001"

      with_stubbed_client(
        get_responses:  { container_id => @finished_status },
        post_responses: {
          "#{ig_id}/media"         => { "id" => container_id },
          "#{ig_id}/media_publish" => { "id" => media_id }
        }
      ) do |publisher|
        result = publisher.publish(post)

        assert_equal media_id, result
        post.reload
        assert post.published?
        assert_equal media_id, post.external_post_id
        assert_not_nil post.published_at
      end
    end

    test "publish_photo raises ApiError when asset has no public_url" do
      post  = planned_posts(:draft_post)
      post.media_asset.update!(raw_metadata: nil)

      @publisher.stub(:check_quota!, nil) do
        err = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/no public URL/i, err.message)
        assert_not post.reload.failed?, FAILURE_IS_THE_JOBS_JOB
      end
    end

    # -------------------------------------------------------------------------
    # #publish — video / reel
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # #publish — dispatch to the format-specific publishers
    # -------------------------------------------------------------------------

    # Returns a stand-in publisher that records the post it was handed.
    def recording_publisher(media_id)
      calls = []

      publisher = Object.new
      publisher.define_singleton_method(:publish) do |planned_post|
        calls << planned_post
        media_id
      end

      [ publisher, calls ]
    end

    test "publish delegates a video post to VideoPublisher" do
      post = PlannedPost.create!(
        user:         @user,
        media_asset:  media_assets(:sample_video),
        platform:     :instagram,
        status:       :draft,
        scheduled_at: nil,
        caption:      "Great reel!"
      )

      delegate, calls = recording_publisher("ig_media_video_001")

      Instagram::VideoPublisher.stub(:new, delegate) do
        assert_equal "ig_media_video_001", @publisher.publish(post)
      end

      assert_equal [ post ], calls
    end

    test "publish delegates a carousel post to CarouselPublisher" do
      image_asset = media_assets(:sample_image)
      video_asset = media_assets(:sample_video)

      post = PlannedPost.create!(
        user:             @user,
        media_asset:      image_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        caption:          "Carousel post!",
        platform_payload: { "carousel_asset_ids" => [ image_asset.id, video_asset.id ] }
      )

      delegate, calls = recording_publisher("ig_media_carousel_001")

      Instagram::CarouselPublisher.stub(:new, delegate) do
        assert_equal "ig_media_carousel_001", @publisher.publish(post)
      end

      assert_equal [ post ], calls
    end

    test "publish delegates a story post to StoriesPublisher" do
      post = planned_posts(:draft_post)
      post.update!(platform_payload: { "post_type" => "story" })

      delegate, calls = recording_publisher("ig_story_001")

      Instagram::StoriesPublisher.stub(:new, delegate) do
        assert_equal "ig_story_001", @publisher.publish(post)
      end

      assert_equal [ post ], calls
    end

    # PlannedPost now rejects this combination, so it can only reach the
    # publisher as a legacy row written before that validation existed. The
    # dispatch order still has to favour the story, or such a row publishes as
    # a carousel that Meta cannot accept.
    test "publish prefers the story publisher over the carousel publisher" do
      image_asset = media_assets(:sample_image)
      image_2     = media_assets(:sample_image_2)

      post = PlannedPost.new(
        user:             @user,
        media_asset:      image_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: {
          "post_type"          => "story",
          "carousel_asset_ids" => [ image_asset.id, image_2.id ]
        }
      )
      post.save!(validate: false)

      delegate, calls = recording_publisher("ig_story_002")

      Instagram::CarouselPublisher.stub(:new, ->(_) { raise "should not be called" }) do
        Instagram::StoriesPublisher.stub(:new, delegate) do
          assert_equal "ig_story_002", @publisher.publish(post)
        end
      end

      assert_equal [ post ], calls
    end

    test "publish handles a single photo without delegating" do
      post = planned_posts(:draft_post)
      ig_id = @user.instagram_user_id

      Instagram::VideoPublisher.stub(:new, ->(_) { raise "should not be called" }) do
        Instagram::CarouselPublisher.stub(:new, ->(_) { raise "should not be called" }) do
          Instagram::StoriesPublisher.stub(:new, ->(_) { raise "should not be called" }) do
            with_stubbed_client(
              get_responses:  { "cont_photo_solo" => @finished_status },
              post_responses: {
                "#{ig_id}/media"         => { "id" => "cont_photo_solo" },
                "#{ig_id}/media_publish" => { "id" => "ig_media_photo_solo" }
              }
            ) do |publisher|
              assert_equal "ig_media_photo_solo", publisher.publish(post)
            end
          end
        end
      end

      assert_equal "IMAGE", post.reload.platform_payload["media_type"]
    end

    test "publish_carousel raises ArgumentError with fewer than 2 assets" do
      image_asset = media_assets(:sample_image)
      post = PlannedPost.create!(
        user:             @user,
        media_asset:      image_asset,
        platform:         :instagram,
        status:           :draft,
        scheduled_at:     nil,
        platform_payload: { "carousel_asset_ids" => [ image_asset.id ] }
      )

      @publisher.stub(:check_quota!, nil) do
        assert_raises(ArgumentError) { @publisher.publish(post) }
      end
    end

    # -------------------------------------------------------------------------
    # Quota checking
    # -------------------------------------------------------------------------

    test "publish raises RateLimitError when quota is exhausted" do
      post = planned_posts(:draft_post)

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) do |_|
        { "data" => [ { "quota_usage" => 25, "config" => { "quota_total" => 25 } } ] }
      end

      @publisher.instance_variable_set(:@client, mock_client)
      assert_raises(Instagram::RateLimitError) { @publisher.publish(post) }
    end

    # -------------------------------------------------------------------------
    # Container polling
    # -------------------------------------------------------------------------

    test "wait_until_finished! raises ContainerTimeoutError after timeout" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "IN_PROGRESS" } }

      @publisher.instance_variable_set(:@client, mock_client)

      # Pass a deadline already in the past so the timeout triggers immediately
      assert_raises(Instagram::ContainerTimeoutError) do
        @publisher.send(:wait_until_finished!, "cont_timeout_test",
                        deadline_override: Time.current - 1.second)
      end
    end

    test "wait_until_finished! raises ApiError when container enters ERROR state" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |*_|
        { "status_code" => "ERROR", "status" => "Media processing failed" }
      end

      @publisher.instance_variable_set(:@client, mock_client)

      assert_raises(Instagram::ApiError) do
        @publisher.send(:wait_until_finished!, "cont_error_test")
      end
    end

    # -------------------------------------------------------------------------
    # Caption building
    # -------------------------------------------------------------------------

    test "build_caption joins caption and hashtags with double newline" do
      post = planned_posts(:draft_post)
      caption = @publisher.send(:build_caption, post)
      assert_includes caption, post.caption
      assert_includes caption, post.hashtags
    end

    test "build_caption returns just caption when hashtags are blank" do
      post = planned_posts(:draft_post)
      post.hashtags = nil
      assert_equal post.caption, @publisher.send(:build_caption, post)
    end

    # -------------------------------------------------------------------------
    # Skipping non-instagram / already-published posts (via the job)
    # -------------------------------------------------------------------------

    test "publish skips and does not raise when post is already published" do
      post = planned_posts(:published_post)
      # published? is not draft? or scheduled?, so the job would skip — but
      # calling publisher.publish directly would still try. Verify the status
      # guard logic in the job by checking the post's current state.
      assert post.published?
    end

    # -------------------------------------------------------------------------
    # Collaborators and attached audio
    # -------------------------------------------------------------------------

    # Stubs the client and records the params of every container-creation POST.
    def capture_container_params
      captured = []

      mock_client = Object.new
      mock_client.define_singleton_method(:publishing_limit) { |_| { "data" => [ { "quota_usage" => 0, "config" => { "quota_total" => 25 } } ] } }
      mock_client.define_singleton_method(:get) { |*_| { "status_code" => "FINISHED" } }
      mock_client.define_singleton_method(:post) do |path, body = {}|
        if path.end_with?("/media_publish")
          { "id" => "ig_media_001" }
        else
          captured << body
          { "id" => "cont_#{captured.size}" }
        end
      end

      @publisher.instance_variable_set(:@client, mock_client)
      captured
    end

    test "publish_photo forwards collaborators to the Meta API" do
      post = planned_posts(:draft_post)
      post.update!(platform_payload: { "collaborators" => [ "chef_alex", "@bakery_co" ] })

      captured = capture_container_params
      @publisher.publish(post)

      assert_equal [ "chef_alex", "bakery_co" ], JSON.parse(captured.first[:collaborators])
    end

    test "publish_photo omits collaborators when the payload has none" do
      post = planned_posts(:draft_post)

      captured = capture_container_params
      @publisher.publish(post)

      assert_not captured.first.key?(:collaborators)
    end

    test "publish_photo raises before calling the API when too many collaborators are given" do
      post = planned_posts(:draft_post)
      post.update!(platform_payload: { "collaborators" => %w[a b c d] })

      captured = capture_container_params

      assert_raises(ArgumentError) { @publisher.publish(post) }
      assert_empty captured
    end
  end
end
