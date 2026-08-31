# frozen_string_literal: true

module Instagram
  # Publishes a single video (Reel) to Instagram via the Meta Content Publishing API.
  #
  # Instagram video posts are published as Reels by default.  The service supports
  # all optional Reels-specific parameters exposed by the Meta API, including a
  # custom cover image, feed sharing preference, and thumbnail offset.
  #
  # The Meta API flow is:
  #   1. Create a media container with `media_type=REELS`  → returns creation_id
  #   2. Poll the container until status == FINISHED
  #      (video processing can take several minutes for long clips)
  #   3. Publish the container  → returns ig_media_id
  #
  # Usage with a PlannedPost:
  #   publisher = Instagram::VideoPublisher.new(user)
  #   publisher.publish(planned_post)
  #
  #   # The PlannedPost's media_asset must be of media_type :video.
  #   # Optional Reels parameters can be supplied via platform_payload:
  #   #   {
  #   #     "share_to_feed"  => true,          # also appear in main feed (default: true)
  #   #     "cover_url"      => "https://…",   # custom thumbnail image URL
  #   #     "thumb_offset"   => 1000,          # ms into video to use as thumbnail
  #   #     "audio_name"     => "My Track",    # renames YOUR original audio
  #   #     "collaborators"  => ["ig_user_1"], # up to 3 collaborator usernames
  #   #     "location_id"    => "123456789",   # Facebook Page ID for a location tag
  #   #     "audio_id"       => "5877845410",  # attach a track (Instagram::AudioService)
  #   #     "audio_configuration" => {         # …or the long form with volumes
  #   #       "audio_id" => "5877845410", "audio_volume" => 80, "video_volume" => 50
  #   #     }
  #   #   }
  #
  #   # Note: audio_name only renames a Reel's own original audio. To attach a
  #   # track from Instagram's catalogue use audio_id / audio_configuration.
  #
  # The service updates the PlannedPost record on success (status: published,
  # external_post_id, published_at) and on failure (status: failed).
  class VideoPublisher
    # How long to wait between container status polling attempts.
    POLL_INTERVAL_SECONDS = 5
    # Total seconds before declaring a container stuck.
    # Videos can take longer to process than images.
    POLL_TIMEOUT_SECONDS  = 600

    # Optional platform_payload keys forwarded to the Meta API as-is.
    # Keys are mapped from the snake_case payload format to the Meta API param names.
    #
    # collaborators and audio_configuration are built separately via
    # Instagram::PublishOptions because they need JSON encoding and validation.
    OPTIONAL_PARAMS = {
      "cover_url"    => :cover_url,
      "thumb_offset" => :thumb_offset,
      "audio_name"   => :audio_name,
      "location_id"  => :location_id
    }.freeze

    # @param user [User] must have instagram_user_id + instagram_access_token set
    def initialize(user)
      @user   = user
      @client = Instagram::ApiClient.new(user)
    end

    # Publish a video (Reel) for the given planned post.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the Instagram media ID (ig_media_id)
    # @raise [ArgumentError]             when the asset is not a video
    # @raise [Instagram::ApiError]       on Meta API errors
    # @raise [Instagram::RateLimitError] when the 25-posts/24 h quota is exhausted
    # @raise [Instagram::ContainerTimeoutError] when the container does not finish in time
    def publish(planned_post)
      check_quota!

      asset = planned_post.media_asset
      validate_video_asset!(asset)

      creation_id = create_video_container(asset, planned_post)
      wait_until_finished!(creation_id)
      ig_media_id = publish_container(creation_id)

      planned_post.update!(
        status:           :published,
        external_post_id: ig_media_id,
        published_at:     Time.current,
        platform_payload: planned_post.platform_payload.to_h.merge(
          "ig_media_id"   => ig_media_id,
          "container_id"  => creation_id,
          "media_type"    => "REELS"
        )
      )

      ig_media_id
    rescue Instagram::Error
      planned_post.update!(status: :failed)
      raise
    end

    private

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def validate_video_asset!(asset)
      unless asset.video?
        raise ArgumentError,
              "VideoPublisher requires a video MediaAsset (got media_type=#{asset.media_type} " \
              "for MediaAsset##{asset.id}). Use Instagram::CarouselPublisher for images."
      end

      resolve_public_url!(asset) # raises if missing
    end

    # ------------------------------------------------------------------
    # Meta API calls
    # ------------------------------------------------------------------

    # Step 1 – create the Reel media container.
    #
    # Required:
    #   video_url   – publicly accessible HTTPS URL of the video file
    #   media_type  – always "REELS" for Instagram video posts
    #
    # Optional (from platform_payload):
    #   caption, cover_url, thumb_offset, audio_name, location_id,
    #   collaborators, audio_configuration, share_to_feed
    #
    # @param asset        [MediaAsset]
    # @param planned_post [PlannedPost]
    # @return [String] creation_id
    def create_video_container(asset, planned_post)
      payload = planned_post.platform_payload.to_h

      params = {
        video_url:     resolve_public_url!(asset),
        media_type:    "REELS",
        share_to_feed: share_to_feed(payload)
      }

      caption = build_caption(planned_post)
      params[:caption] = caption if caption.present?

      # Forward optional Reels-specific parameters when present in platform_payload.
      OPTIONAL_PARAMS.each do |payload_key, api_key|
        value = payload[payload_key]
        next if value.nil?

        params[api_key] = value.to_s
      end

      # Collaborators and attached audio are JSON-encoded and validated.
      collaborators = Instagram::PublishOptions.collaborators(payload)
      params[:collaborators] = collaborators if collaborators

      audio_configuration = Instagram::PublishOptions.audio_configuration(payload)
      params[:audio_configuration] = audio_configuration if audio_configuration

      Rails.logger.debug("[Instagram::VideoPublisher] Creating video container for MediaAsset##{asset.id}")

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
    # Videos use a longer default timeout than images because encoding can take minutes.
    def wait_until_finished!(creation_id, timeout: POLL_TIMEOUT_SECONDS)
      deadline = Time.current + timeout.seconds

      loop do
        result      = @client.get(creation_id, fields: "status_code,status")
        status_code = result["status_code"]

        case status_code
        when "FINISHED"
          Rails.logger.debug("[Instagram::VideoPublisher] Container #{creation_id} is FINISHED.")
          return
        when "ERROR", "EXPIRED"
          raise Instagram::ApiError,
                "Container #{creation_id} entered terminal status '#{status_code}': #{result["status"]}"
        else
          # IN_PROGRESS or other transient states — keep polling
          Rails.logger.debug(
            "[Instagram::VideoPublisher] Container #{creation_id} status: #{status_code}. " \
            "Retrying in #{POLL_INTERVAL_SECONDS}s…"
          )
        end

        if Time.current >= deadline
          raise Instagram::ContainerTimeoutError,
                "Video container #{creation_id} did not finish processing within #{timeout}s"
        end

        sleep POLL_INTERVAL_SECONDS
      end
    end

    # Check the 25-posts/24 h quota before attempting to publish.
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

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def ig_user_id
      @ig_user_id ||= @user.instagram_user_id.presence ||
        raise(Instagram::ApiError, "User #{@user.id} has no instagram_user_id set")
    end

    def build_caption(planned_post)
      parts = [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?)
      parts.join("\n\n")
    end

    # Determine whether to share to the main feed.
    # Defaults to true when not specified in platform_payload.
    def share_to_feed(payload)
      value = payload["share_to_feed"]
      value.nil? ? "true" : value.to_s
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
