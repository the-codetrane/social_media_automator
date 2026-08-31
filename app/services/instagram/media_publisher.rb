# frozen_string_literal: true

module Instagram
  # Entry point for publishing a PlannedPost to Instagram.
  #
  # This class decides *which* kind of post it is looking at and hands the work
  # to the matching format-specific publisher:
  #
  #   story    → Instagram::StoriesPublisher
  #   carousel → Instagram::CarouselPublisher
  #   video    → Instagram::VideoPublisher
  #   image    → published here (single photos need no dedicated class)
  #
  # Each specialized publisher owns its own container parameters, polling
  # timeouts and PlannedPost bookkeeping, so optional features — collaborators,
  # attached audio, cover images, location tags — are available through this
  # entry point too.
  #
  # Usage:
  #   publisher = Instagram::MediaPublisher.new(user)
  #   publisher.publish(planned_post)
  #
  # For carousel posts, set planned_post.platform_payload["carousel_asset_ids"]
  # to an ordered array of MediaAsset IDs before calling publish.
  class MediaPublisher
    # How long to wait between status polling attempts for a photo container.
    POLL_INTERVAL_SECONDS = 5
    # Give up after this many total seconds of polling.
    POLL_TIMEOUT_SECONDS  = 300

    # @param user [User] must have instagram_user_id + instagram_access_token set
    def initialize(user)
      @user   = user
      @client = Instagram::ApiClient.new(user)
    end

    # Determine the correct publish method from the post's MediaAsset and dispatch.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the Instagram media ID (ig_media_id)
    def publish(planned_post)
      validate_carousel_asset_count!(planned_post)

      if story_post?(planned_post)
        publish_story(planned_post)
      elsif carousel_post?(planned_post)
        publish_carousel(planned_post)
      elsif planned_post.media_asset.video?
        publish_video(planned_post)
      else
        publish_photo(planned_post)
      end
    end

    # ------------------------------------------------------------------
    # Content-type-specific publish methods (also callable directly)
    # ------------------------------------------------------------------

    # Publish a single image or video as an Instagram Story.
    # Stories do not support captions, collaborators or attached audio.
    #
    # @param planned_post [PlannedPost]
    # @return [String] ig_media_id
    def publish_story(planned_post)
      Instagram::StoriesPublisher.new(@user).publish(planned_post)
    end

    # Publish a single video as a Reel.
    #
    # Optional platform_payload keys: "collaborators", "audio_id" /
    # "audio_configuration", "cover_url", "thumb_offset", "audio_name",
    # "location_id", "share_to_feed".
    #
    # @param planned_post [PlannedPost]
    # @return [String] ig_media_id
    def publish_video(planned_post)
      Instagram::VideoPublisher.new(@user).publish(planned_post)
    end

    # Publish a carousel of images and/or videos.
    # Reads carousel_asset_ids from planned_post.platform_payload.
    #
    # Optional platform_payload keys: "collaborators".
    #
    # @param planned_post [PlannedPost]
    # @return [String] ig_media_id
    def publish_carousel(planned_post)
      Instagram::CarouselPublisher.new(@user).publish(planned_post)
    end

    # Publish a single photo.
    # Requires planned_post.media_asset to be an image with a public_url.
    #
    # Optional platform_payload keys: "collaborators".
    #
    # @param planned_post [PlannedPost]
    # @return [String] ig_media_id
    def publish_photo(planned_post)
      check_quota!

      asset = planned_post.media_asset

      params = {
        image_url: resolve_public_url!(asset),
        caption:   build_caption(planned_post)
      }

      collaborators = Instagram::PublishOptions.collaborators(planned_post.platform_payload)
      params[:collaborators] = collaborators if collaborators

      creation_id = create_container(params)
      wait_until_finished!(creation_id)
      ig_media_id = publish_container(creation_id)

      planned_post.update!(
        status:           :published,
        external_post_id: ig_media_id,
        published_at:     Time.current,
        platform_payload: planned_post.platform_payload.to_h.merge(
          "ig_media_id"  => ig_media_id,
          "container_id" => creation_id,
          "media_type"   => "IMAGE"
        )
      )

      ig_media_id
    rescue Instagram::Error
      planned_post.update!(status: :failed)
      raise
    end

    private

    def ig_user_id
      @ig_user_id ||= @user.instagram_user_id.presence ||
        raise(Instagram::ApiError, "User #{@user.id} has no instagram_user_id set")
    end

    # POST /{ig-user-id}/media
    def create_container(params)
      result = @client.post("#{ig_user_id}/media", params)
      result["id"] || raise(Instagram::ApiError, "No container ID returned: #{result.inspect}")
    end

    # POST /{ig-user-id}/media_publish
    def publish_container(creation_id)
      result = @client.post("#{ig_user_id}/media_publish", creation_id: creation_id)
      result["id"] || raise(Instagram::ApiError, "No media ID returned: #{result.inspect}")
    end

    # Poll GET /{creation_id}?fields=status_code until FINISHED or timeout.
    def wait_until_finished!(creation_id, deadline_override: nil)
      deadline = deadline_override || (Time.current + POLL_TIMEOUT_SECONDS.seconds)

      loop do
        result      = @client.get(creation_id, fields: "status_code,status")
        status_code = result["status_code"]

        case status_code
        when "FINISHED"
          return
        when "ERROR", "EXPIRED"
          raise Instagram::ApiError, "Container #{creation_id} entered status '#{status_code}': #{result["status"]}"
        else
          # IN_PROGRESS or other transient states — keep polling
        end

        raise Instagram::ContainerTimeoutError, "Container #{creation_id} did not finish within #{POLL_TIMEOUT_SECONDS}s" if Time.current >= deadline

        sleep POLL_INTERVAL_SECONDS
      end
    end

    # Check the publishing quota before attempting to publish.
    def check_quota!
      data   = @client.publishing_limit(ig_user_id)
      record = Array(data["data"]).first || {}
      config = record["config"] || {}
      usage  = record["quota_usage"].to_i
      limit  = config["quota_total"].to_i

      if limit.positive? && usage >= limit
        raise Instagram::RateLimitError, "Instagram publishing quota exhausted (#{usage}/#{limit} posts in the last 24 h)"
      end
    end

    def build_caption(planned_post)
      parts = [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?)
      parts.join("\n\n")
    end

    def story_post?(planned_post)
      planned_post.platform_payload&.dig("post_type") == "story"
    end

    def carousel_post?(planned_post)
      carousel_asset_ids(planned_post).size > 1
    end

    def validate_carousel_asset_count!(planned_post)
      explicit_ids = planned_post.platform_payload&.dig("carousel_asset_ids")
      return unless explicit_ids.present?
      raise ArgumentError, "Carousel requires at least 2 items" if explicit_ids.size < 2
    end

    def carousel_asset_ids(planned_post)
      ids = planned_post.platform_payload&.dig("carousel_asset_ids")
      ids.presence || [ planned_post.media_asset_id ]
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
