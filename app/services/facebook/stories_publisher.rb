# frozen_string_literal: true

module Facebook
  # Publishes a single image or video as a Facebook Page Story.
  #
  # Page Stories are a separate API from the Page feed — a story cannot be
  # created by posting to /feed with a flag — and the two media types take
  # different routes:
  #
  #   Photo (2 steps)
  #     1. POST /{page-id}/photos with published=false   → photo_id
  #     2. POST /{page-id}/photo_stories?photo_id=…      → post_id
  #
  #   Video (3 steps)
  #     1. POST /{page-id}/video_stories?upload_phase=start → video_id, upload_url
  #     2. POST {upload_url} with a `file_url` header       → Meta fetches the file
  #     3. POST /{page-id}/video_stories?upload_phase=finish&video_id=… → post_id
  #
  # Step 2 is asynchronous: Meta downloads and transcodes the file on its own
  # schedule, and calling `finish` before that completes fails, so the upload and
  # processing phases are polled in between.
  #
  # Usage:
  #   Facebook::StoriesPublisher.new(user).publish(planned_post)
  #
  # The service updates the PlannedPost on success (status: published,
  # external_post_id, published_at) and marks it failed on any Meta error.
  #
  # Requirements per Meta's Page Stories documentation:
  #   - Permissions: pages_manage_posts, pages_read_engagement, pages_show_list
  #   - Photos: JPEG/PNG/BMP/GIF/TIFF, max 10 MB
  #   - Videos: MP4, 9:16, 1080x1920 (min 540x960), 3–60 s, H.264/H.265, AAC audio
  #   - A story is visible for 24 hours, and takes no caption or scheduled time
  class StoriesPublisher
    # How long to wait between video status polls.
    POLL_INTERVAL_SECONDS = 5
    # Total seconds before declaring an upload stuck.
    POLL_TIMEOUT_SECONDS  = 300

    # Terminal values of each phase in GET /{video-id}?fields=status.
    PHASE_COMPLETE = "complete"
    PHASE_ERROR    = "error"

    # The phases that must finish before `upload_phase=finish` will succeed.
    # publishing_phase only starts once finish is called, so it is not waited on.
    UPLOAD_PHASES = %w[uploading_phase processing_phase].freeze

    # @param user [User] must have instagram_page_id + instagram_access_token set
    def initialize(user)
      @user    = user
      @page_id = Facebook::PageToken.page_id_for!(user)
    end

    # Publish a PlannedPost's media asset as a Page Story.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the Facebook post ID
    # @raise [Instagram::ApiError]              on Meta API errors
    # @raise [Instagram::ContainerTimeoutError] when the video never finishes processing
    def publish(planned_post)
      asset = planned_post.media_asset
      validate_asset!(asset)

      post_id, extra = asset.video? ? publish_video_story(asset) : publish_photo_story(asset)

      planned_post.update!(
        status:           :published,
        external_post_id: post_id,
        published_at:     Time.current,
        platform_payload: planned_post.platform_payload.to_h.merge(extra).merge("media_type" => "STORY")
      )

      post_id
      # NOTE: deliberately no `rescue Instagram::Error` that marks the post
      # failed.  Doing so set status to :failed on the *first* attempt, and
      # PublishFacebookPostJob#perform only proceeds for a scheduled or draft
      # post — so every retry short-circuited and the retry_on rules for
      # ApiError, RateLimitError and ContainerTimeoutError never did anything.
      # The job owns failure marking (its MARK_FAILED handler), which runs when
      # retries are exhausted or the error was never retryable.
    end

    private

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def validate_asset!(asset)
      if asset.blank?
        raise Instagram::ApiError, "A story needs a media asset"
      end

      unless asset.image? || asset.video?
        raise Instagram::ApiError,
              "MediaAsset #{asset.id} is #{asset.media_type} — a story must be an image or a video"
      end

      # PlannedPost checks these too, but a post written before that validation
      # existed — or a direct call to this publisher — would otherwise spend a
      # whole upload before Meta rejects the file.
      violations = StoryMediaSpec.for("facebook").errors_for(asset)
      if violations.any?
        raise Instagram::ApiError, "MediaAsset #{asset.id} #{violations.join('; ')}"
      end

      resolve_public_url!(asset) # raises when there is nothing for Meta to fetch
    end

    # ------------------------------------------------------------------
    # Photo stories
    # ------------------------------------------------------------------

    # @return [Array(String, Hash)] post ID and extra platform_payload keys
    def publish_photo_story(asset)
      Rails.logger.debug("[Facebook::StoriesPublisher] Uploading photo story for MediaAsset##{asset.id}")

      upload = client.post(
        "#{@page_id}/photos",
        url:       resolve_public_url!(asset),
        published: "false"
      )

      photo_id = upload["id"].presence ||
        raise(Instagram::ApiError, "No photo ID returned for MediaAsset##{asset.id}: #{upload.inspect}")

      result = client.post("#{@page_id}/photo_stories", photo_id: photo_id)

      [ story_post_id!(result), { "photo_id" => photo_id } ]
    end

    # ------------------------------------------------------------------
    # Video stories
    # ------------------------------------------------------------------

    # @return [Array(String, Hash)] post ID and extra platform_payload keys
    def publish_video_story(asset)
      Rails.logger.debug("[Facebook::StoriesPublisher] Starting video story upload for MediaAsset##{asset.id}")

      session    = client.post("#{@page_id}/video_stories", upload_phase: "start")
      video_id   = session["video_id"].presence ||
        raise(Instagram::ApiError, "No video ID returned starting the upload: #{session.inspect}")
      upload_url = session["upload_url"].presence ||
        raise(Instagram::ApiError, "No upload URL returned starting the upload: #{session.inspect}")

      # Meta pulls the file itself from the URL we hand it, so nothing is
      # streamed through this process.
      client.post_upload(upload_url, "file_url" => resolve_public_url!(asset))

      wait_until_processed!(video_id)

      result = client.post("#{@page_id}/video_stories", upload_phase: "finish", video_id: video_id)

      [ story_post_id!(result), { "video_id" => video_id } ]
    end

    # Poll GET /{video-id}?fields=status until Meta has fetched and transcoded
    # the video. `upload_phase=finish` before that returns an error, so this wait
    # is not optional.
    def wait_until_processed!(video_id, timeout: POLL_TIMEOUT_SECONDS)
      deadline = Time.current + timeout.seconds

      loop do
        status = client.get(video_id, fields: "status")["status"].to_h

        UPLOAD_PHASES.each { |phase| check_phase_error!(video_id, status, phase) }

        if status.dig("processing_phase", "status") == PHASE_COMPLETE
          Rails.logger.debug("[Facebook::StoriesPublisher] Video #{video_id} finished processing.")
          return
        end

        if Time.current >= deadline
          raise Instagram::ContainerTimeoutError,
                "Video story #{video_id} did not finish processing within #{timeout}s " \
                "(#{describe_phases(status)})"
        end

        Rails.logger.debug(
          "[Facebook::StoriesPublisher] Video #{video_id} #{describe_phases(status)}. " \
          "Retrying in #{POLL_INTERVAL_SECONDS}s…"
        )

        sleep POLL_INTERVAL_SECONDS
      end
    end

    # A failed phase is terminal — Meta will not retry it — so surface its
    # message instead of polling until the timeout.
    def check_phase_error!(video_id, status, phase)
      return unless status.dig(phase, "status") == PHASE_ERROR

      raise Instagram::ApiError,
            "Video story #{video_id} failed during #{phase.tr('_', ' ')}: #{phase_error_message(status[phase])}"
    end

    def phase_error_message(phase)
      messages = Array(phase["errors"]).filter_map { |error| error["message"] || error["error_message"] }
      return messages.join("; ") if messages.any?

      phase.dig("error", "message").presence || "no error detail returned"
    end

    def describe_phases(status)
      UPLOAD_PHASES.map { |phase| "#{phase.tr('_', ' ')}: #{status.dig(phase, 'status') || 'unknown'}" }.join(", ")
    end

    # ------------------------------------------------------------------
    # Shared helpers
    # ------------------------------------------------------------------

    # Both story endpoints answer with { "success": true, "post_id": "…" }.
    def story_post_id!(result)
      result["post_id"].presence ||
        raise(Instagram::ApiError, "Story publish returned no post_id: #{result.inspect}")
    end

    # Page-level writes need a Page token, not the stored user token.
    def client
      @client ||= Instagram::ApiClient.new(@user, access_token: Facebook::PageToken.fetch(@user, @page_id))
    end

    def resolve_public_url!(asset)
      url = asset.public_url

      if url.blank?
        raise Instagram::ApiError,
              "MediaAsset #{asset.id} has no public URL. " \
              "Attach a file via ActiveStorage or set raw_metadata[\"public_url\"]."
      end

      url
    end
  end
end
