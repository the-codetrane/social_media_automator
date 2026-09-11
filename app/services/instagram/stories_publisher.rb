# frozen_string_literal: true

module Instagram
  # Publishes a single image or video as an Instagram Story via the Meta Content Publishing API.
  #
  # Instagram Stories support a single image or video per story "card". The media
  # is displayed in portrait format (9:16 aspect ratio recommended) and disappears
  # after 24 hours.
  #
  # The Meta API flow for Stories:
  #   1. Create a media container with `media_type=STORIES`  → returns creation_id
  #   2. Poll the container until status == FINISHED
  #   3. Publish the container  → returns ig_media_id
  #
  # Usage with a PlannedPost:
  #   publisher = Instagram::StoriesPublisher.new(user)
  #   publisher.publish(planned_post)
  #
  #   # The PlannedPost's media_asset can be an image or video.
  #   # Note: Stories do NOT support captions, collaborators or attached audio
  #   # via the API, but stickers and other overlays can be added natively in
  #   # the Instagram app.
  #
  # The service updates the PlannedPost record on success (status: published,
  # external_post_id, published_at) and on failure (status: failed).
  #
  # Requirements per Meta API documentation:
  #   - Images: JPEG format, max 8MB
  #   - Videos: MP4/MOV, H.264 codec, AAC audio, max 100MB, 3-60 seconds
  #   - Aspect ratio: 9:16 recommended (1080x1920 pixels)
  class StoriesPublisher
    # How long to wait between container status polling attempts.
    POLL_INTERVAL_SECONDS = 5
    # Total seconds before declaring a container stuck.
    # Videos can take longer to process.
    POLL_TIMEOUT_SECONDS  = 300

    # @param user [User] must have instagram_user_id + instagram_access_token set
    def initialize(user)
      @user   = user
      @client = Instagram::ApiClient.new(user)
    end

    # Publish an image or video as an Instagram Story.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the Instagram media ID (ig_media_id)
    # @raise [Instagram::ApiError]             on Meta API errors
    # @raise [Instagram::RateLimitError]       when the 25-posts/24 h quota is exhausted
    # @raise [Instagram::ContainerTimeoutError] when the container does not finish in time
    def publish(planned_post)
      check_quota!

      asset = planned_post.media_asset
      validate_asset!(asset)

      creation_id = create_story_container(asset)
      wait_until_finished!(creation_id)
      ig_media_id = publish_container(creation_id)

      planned_post.update!(
        status:           :published,
        external_post_id: ig_media_id,
        published_at:     Time.current,
        platform_payload: planned_post.platform_payload.to_h.merge(
          "ig_media_id"  => ig_media_id,
          "container_id" => creation_id,
          "media_type"   => "STORIES"
        )
      )

      ig_media_id
    rescue Instagram::Error => e
      # mark_failed! rather than update!: a post can be invalid for the very
      # reason it failed — an over-long story video trips PlannedPost's own
      # media limits — and update! would raise from the rescue, hiding the
      # error that actually explains the failure.
      planned_post.mark_failed!(e.message)
      raise
    end

    private

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def validate_asset!(asset)
      # PlannedPost checks these too, but a post written before that validation
      # existed — or a direct call to this publisher — would otherwise burn one
      # of the 25 daily publishes before Meta rejects the file.
      violations = StoryMediaSpec.for("instagram").errors_for(asset)
      if violations.any?
        raise Instagram::ApiError, "MediaAsset #{asset.id} #{violations.join('; ')}"
      end

      resolve_public_url!(asset) # raises if missing
    end

    # ------------------------------------------------------------------
    # Meta API calls
    # ------------------------------------------------------------------

    # Create a STORIES media container.
    #
    # @param asset [MediaAsset]
    # @return [String] creation_id
    def create_story_container(asset)
      params = { media_type: "STORIES" }

      if asset.video?
        params[:video_url] = resolve_public_url!(asset)
      else
        params[:image_url] = resolve_public_url!(asset)
      end

      Rails.logger.debug(
        "[Instagram::StoriesPublisher] Creating story container for MediaAsset##{asset.id} (#{asset.media_type})"
      )

      create_container(params)
    end

    # POST /{ig-user-id}/media → returns the new container's creation_id
    def create_container(params)
      result = @client.post("#{ig_user_id}/media", params)
      result["id"] || raise(Instagram::ApiError, "No container ID returned: #{result.inspect}")
    end

    # POST /{ig-user-id}/media_publish → returns the published media's ig_media_id
    def publish_container(creation_id)
      result = @client.post("#{ig_user_id}/media_publish", creation_id: creation_id)
      result["id"] || raise(Instagram::ApiError, "No media ID returned: #{result.inspect}")
    end

    # Poll GET /{creation_id}?fields=status_code,status until FINISHED or timeout.
    def wait_until_finished!(creation_id, timeout: POLL_TIMEOUT_SECONDS)
      deadline = Time.current + timeout.seconds

      loop do
        result      = @client.get(creation_id, fields: "status_code,status")
        status_code = result["status_code"]

        case status_code
        when "FINISHED"
          Rails.logger.debug("[Instagram::StoriesPublisher] Container #{creation_id} is FINISHED.")
          return
        when "ERROR", "EXPIRED"
          raise Instagram::ApiError,
                "Container #{creation_id} entered terminal status '#{status_code}': #{result["status"]}"
        else
          # IN_PROGRESS or other transient states — keep polling
          Rails.logger.debug(
            "[Instagram::StoriesPublisher] Container #{creation_id} status: #{status_code}. " \
            "Retrying in #{POLL_INTERVAL_SECONDS}s…"
          )
        end

        if Time.current >= deadline
          raise Instagram::ContainerTimeoutError,
                "Story container #{creation_id} did not finish processing within #{timeout}s"
        end

        sleep POLL_INTERVAL_SECONDS
      end
    end

    # Check the 25-posts/24 h quota before attempting to publish.
    # Note: Stories count toward the same daily publishing limit.
    def check_quota!
      data   = @client.publishing_limit(ig_user_id)
      record = Array(data["data"]).first || {}
      config = record["config"] || {}
      usage  = record["quota_usage"].to_i
      limit  = config["quota_total"].to_i

      if limit.positive? && usage >= limit
        raise Instagram::RateLimitError,
              "Instagram publishing quota exhausted (#{usage}/#{limit} posts in the last 24 h)"
      end
    end

    def ig_user_id
      @ig_user_id ||= @user.instagram_user_id.presence ||
        raise(Instagram::ApiError, "User #{@user.id} has no instagram_user_id set")
    end

    # Return the public HTTPS URL for a MediaAsset.
    # Uses ActiveStorage (DigitalOcean Spaces) or falls back to raw_metadata["public_url"].
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
