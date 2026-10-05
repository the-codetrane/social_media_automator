# frozen_string_literal: true

require "test_helper"

module Facebook
  class StoriesPublisherTest < ActiveSupport::TestCase
    # The publisher raises and leaves the post alone; PublishFacebookPostJob
    # marks it failed once retries are exhausted or the error was never
    # retryable.  The publisher used to do this itself, which tripped the
    # job's status guard on every retry and made retry_on inert.
    FAILURE_IS_THE_JOBS_JOB =
      "the publisher must not mark the post failed — that is the job's call, " \
      "and doing it here breaks every retry"

    def setup
      @user      = users(:one)
      @page_id   = @user.instagram_page_id
      @publisher = Facebook::StoriesPublisher.new(@user)
    end

    def story_post(asset: media_assets(:sample_image), **overrides)
      post = PlannedPost.new({
        user:             @user,
        media_asset:      asset,
        platform:         :facebook,
        status:           :draft,
        caption:          "Ignored on a story",
        platform_payload: { "post_type" => "story" }
      }.merge(overrides))
      post.save!(validate: false)
      post
    end

    # Records every POST/GET so a test can assert on the exact call sequence.
    # `posts` and `gets` are keyed by path, returning canned responses.
    def stub_client(posts: {}, gets: {}, uploads: nil)
      calls = []

      client = Object.new
      client.define_singleton_method(:get) do |path, params = {}|
        # The page-token lookup goes through the same client.
        next { "access_token" => "PAGE_TOKEN" } if params[:fields] == "access_token"

        calls << [ :get, path, params ]
        gets.fetch(path) { raise "Unexpected GET #{path}" }
      end
      client.define_singleton_method(:post) do |path, body = {}|
        calls << [ :post, path, body ]
        response = posts.fetch(path) { raise "Unexpected POST #{path}" }
        response.is_a?(Proc) ? response.call(body) : response
      end
      client.define_singleton_method(:post_upload) do |url, headers = {}|
        calls << [ :upload, url, headers ]
        uploads || { "success" => true }
      end

      [ client, calls ]
    end

    def with_client(client)
      Instagram::ApiClient.stub(:new, ->(_user, **_opts) { client }) { yield }
    end

    # -------------------------------------------------------------------------
    # Photo stories
    # -------------------------------------------------------------------------

    test "publish uploads an unpublished photo then posts it to photo_stories" do
      post = story_post
      client, calls = stub_client(posts: {
        "#{@page_id}/photos"        => { "id" => "photo_001" },
        "#{@page_id}/photo_stories" => { "success" => true, "post_id" => "fb_story_001" }
      })

      with_client(client) do
        assert_equal "fb_story_001", @publisher.publish(post)
      end

      upload, publish = calls.select { |kind, _, _| kind == :post }

      assert_equal "#{@page_id}/photos", upload[1]
      assert_equal "false", upload[2][:published]
      assert_equal media_assets(:sample_image).public_url, upload[2][:url]

      assert_equal "#{@page_id}/photo_stories", publish[1]
      assert_equal "photo_001", publish[2][:photo_id]
    end

    test "publish records the story on the post" do
      post = story_post
      client, = stub_client(posts: {
        "#{@page_id}/photos"        => { "id" => "photo_001" },
        "#{@page_id}/photo_stories" => { "post_id" => "fb_story_001" }
      })

      with_client(client) { @publisher.publish(post) }

      post.reload
      assert post.published?
      assert_equal "fb_story_001", post.external_post_id
      assert_not_nil post.published_at
      assert_equal "photo_001", post.platform_payload["photo_id"]
      assert_equal "STORY", post.platform_payload["media_type"]
      # The post_type key that routed it here survives the publish.
      assert_equal "story", post.platform_payload["post_type"]
    end

    test "publish raises when the photo upload returns no ID" do
      post = story_post
      client, = stub_client(posts: { "#{@page_id}/photos" => { "error_hint" => "nope" } })

      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/No photo ID returned/, error.message)
      end
    end

    # -------------------------------------------------------------------------
    # Video stories
    # -------------------------------------------------------------------------

    test "publish walks a video through start, upload, poll and finish" do
      post  = story_post(asset: media_assets(:sample_video))
      asset = media_assets(:sample_video)

      client, calls = stub_client(
        posts: {
          "#{@page_id}/video_stories" => lambda do |body|
            case body[:upload_phase]
            when "start"  then { "video_id" => "vid_001", "upload_url" => "https://rupload.facebook.com/video-upload/v26.0/vid_001" }
            when "finish" then { "success" => true, "post_id" => "fb_story_vid_001" }
            else raise "Unexpected upload_phase #{body[:upload_phase].inspect}"
            end
          end
        },
        gets: {
          "vid_001" => {
            "status" => {
              "uploading_phase"  => { "status" => "complete" },
              "processing_phase" => { "status" => "complete" }
            }
          }
        }
      )

      with_client(client) do
        assert_equal "fb_story_vid_001", @publisher.publish(post)
      end

      assert_equal %i[post upload get post], calls.map(&:first)

      upload = calls.find { |kind, _, _| kind == :upload }
      assert_equal "https://rupload.facebook.com/video-upload/v26.0/vid_001", upload[1]
      assert_equal asset.public_url, upload[2]["file_url"]

      finish = calls.last
      assert_equal "finish", finish[2][:upload_phase]
      assert_equal "vid_001", finish[2][:video_id]
      assert_equal "vid_001", post.reload.platform_payload["video_id"]
    end

    test "publish raises when starting the upload returns no upload URL" do
      post = story_post(asset: media_assets(:sample_video))
      client, = stub_client(posts: { "#{@page_id}/video_stories" => { "video_id" => "vid_001" } })

      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/No upload URL returned/, error.message)
      end
    end

    test "publish surfaces a failed processing phase instead of polling to the timeout" do
      post = story_post(asset: media_assets(:sample_video))

      client, = stub_client(
        posts: {
          "#{@page_id}/video_stories" => { "video_id" => "vid_002", "upload_url" => "https://rupload.facebook.com/vid_002" }
        },
        gets: {
          "vid_002" => {
            "status" => {
              "uploading_phase"  => { "status" => "complete" },
              "processing_phase" => { "status" => "error", "errors" => [ { "message" => "Resolution too low" } ] }
            }
          }
        }
      )

      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/failed during processing phase/, error.message)
        assert_match(/Resolution too low/, error.message)
      end

      assert_not post.reload.failed?, FAILURE_IS_THE_JOBS_JOB
    end

    test "wait_until_processed! raises ContainerTimeoutError when processing never completes" do
      client, = stub_client(gets: {
        "vid_003" => {
          "status" => {
            "uploading_phase"  => { "status" => "complete" },
            "processing_phase" => { "status" => "in_progress" }
          }
        }
      })
      @publisher.instance_variable_set(:@client, client)

      # Trade the real 5 s sleep for virtual time so the deadline arrives at once.
      test_case = self
      @publisher.define_singleton_method(:sleep) { |seconds| test_case.travel(seconds.seconds) }

      freeze_time do
        error = assert_raises(Instagram::ContainerTimeoutError) do
          @publisher.send(:wait_until_processed!, "vid_003", timeout: 1)
        end

        assert_match(/did not finish processing/, error.message)
        assert_match(/processing phase: in_progress/, error.message)
      end
    end

    # -------------------------------------------------------------------------
    # Validation and failure bookkeeping
    # -------------------------------------------------------------------------

    test "publish raises a descriptive error when the asset has no public URL" do
      post = story_post(asset: media_assets(:sample_image_no_url))

      client, = stub_client
      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/has no public URL/, error.message)
      end

      assert_not post.reload.failed?, FAILURE_IS_THE_JOBS_JOB
    end

    test "publish rejects an audio asset" do
      audio = MediaAsset.create!(
        external_id:   "story-audio-#{SecureRandom.hex(4)}",
        media_type:    :audio,
        status:        :processed,
        first_seen_at: Time.current,
        raw_metadata:  { "public_url" => "https://example.com/track.mp3" }
      )
      post = story_post(asset: audio)

      client, = stub_client
      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/must be an image or a video/, error.message)
      end
    end

    test "publish rejects an over-long video before spending an upload" do
      post = story_post(asset: media_assets(:sample_long_video))

      # Any API call at all is a failure here: the check must come first.
      client, calls = stub_client
      with_client(client) do
        error = assert_raises(Instagram::ApiError) { @publisher.publish(post) }
        assert_match(/3–60 seconds/, error.message)
      end

      assert_empty calls.reject { |kind, _, _| kind == :get }
      assert_not post.reload.failed?, FAILURE_IS_THE_JOBS_JOB
    end

    test "initialize raises when the user has no page ID" do
      @user.update_column(:instagram_page_id, nil)

      error = assert_raises(Instagram::ApiError) { Facebook::StoriesPublisher.new(@user) }
      assert_match(/no Facebook page_id/, error.message)
    end
  end
end
