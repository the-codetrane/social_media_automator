# frozen_string_literal: true

module Instagram
  # Publishes a carousel of images to Instagram via the Meta Content Publishing API.
  #
  # A carousel post requires a minimum of 2 and a maximum of 10 image items.
  # Each image asset must expose a public HTTPS URL via its `raw_metadata["public_url"]`.
  #
  # The Meta API flow is:
  #   1. Create one child media container per image  → returns creation_id per child
  #   2. Poll each child container until status == FINISHED
  #   3. Create a parent CAROUSEL container referencing the children IDs + caption
  #   4. Poll the parent container until status == FINISHED
  #   5. Publish the parent container  → returns ig_media_id
  #
  # Usage with a PlannedPost:
  #   publisher = Instagram::CarouselPublisher.new(user)
  #   publisher.publish(planned_post)
  #
  #   # planned_post.platform_payload must contain:
  #   #   { "carousel_asset_ids" => [id1, id2, ...] }  (ordered array of MediaAsset IDs)
  #   # The primary planned_post.media_asset is treated as the first item when
  #   # carousel_asset_ids is absent (single-asset fallback is rejected — carousels
  #   # need at least 2 items).
  #
  # The service updates the PlannedPost record on success (status: published,
  # external_post_id, published_at) and on failure (status: failed).
  class CarouselPublisher
    # Carousel size limits imposed by the Meta Content Publishing API.
    MIN_ITEMS = 2
    MAX_ITEMS = 10

    # How long to wait between container status polling attempts.
    POLL_INTERVAL_SECONDS = 5
    # Total seconds before declaring a container stuck.
    POLL_TIMEOUT_SECONDS  = 300

    # @param user [User]  must have instagram_user_id + instagram_access_token set
    def initialize(user)
      @user   = user
      @client = Instagram::ApiClient.new(user)
    end

    # Publish a carousel of images for the given planned post.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the Instagram media ID (ig_media_id)
    # @raise [ArgumentError]             when asset list is empty or out of bounds
    # @raise [Instagram::ApiError]       on Meta API errors
    # @raise [Instagram::RateLimitError] when the 25-posts/24 h quota is exhausted
    # @raise [Instagram::ContainerTimeoutError] when a container does not finish in time
    def publish(planned_post)
      check_quota!

      assets = resolve_assets(planned_post)
      validate_assets!(assets)

      child_ids = create_child_containers(assets)
      parent_id = create_parent_container(child_ids, caption: build_caption(planned_post))
      wait_until_finished!(parent_id)

      ig_media_id = publish_container(parent_id)

      planned_post.update!(
        status:           :published,
        external_post_id: ig_media_id,
        published_at:     Time.current,
        platform_payload: planned_post.platform_payload.to_h.merge(
          "ig_media_id"         => ig_media_id,
          "carousel_item_count" => assets.size
        )
      )

      ig_media_id
    rescue Instagram::Error
      planned_post.update!(status: :failed)
      raise
    end

    private

    # ------------------------------------------------------------------
    # Asset resolution & validation
    # ------------------------------------------------------------------

    # Returns an ordered Array<MediaAsset> for the carousel items.
    # Reads carousel_asset_ids from platform_payload; falls back to the
    # post's primary media_asset (which will fail validation if count < 2).
    def resolve_assets(planned_post)
      ids = planned_post.platform_payload&.dig("carousel_asset_ids")

      if ids.present?
        ids.map { |id| MediaAsset.find(id) }
      else
        [ planned_post.media_asset ]
      end
    end

    # Raises ArgumentError for any constraint violation.
    def validate_assets!(assets)
      if assets.size < MIN_ITEMS
        raise ArgumentError,
              "Carousel requires at least #{MIN_ITEMS} items (#{assets.size} provided). " \
              "Set platform_payload[\"carousel_asset_ids\"] to an ordered list of MediaAsset IDs."
      end

      if assets.size > MAX_ITEMS
        raise ArgumentError,
              "Carousel supports at most #{MAX_ITEMS} items (#{assets.size} provided)."
      end

      non_images = assets.reject(&:image?)
      if non_images.any?
        ids = non_images.map(&:id).join(", ")
        raise ArgumentError,
              "All carousel items must be images. Non-image asset IDs: #{ids}. " \
              "Use Instagram::MediaPublisher for mixed-media carousels."
      end

      assets.each do |asset|
        resolve_public_url!(asset) # raises if missing
      end
    end

    # ------------------------------------------------------------------
    # Meta API calls
    # ------------------------------------------------------------------

    # Step 1 – create a child item container for every image asset.
    # Each child container is polled until FINISHED before moving on.
    #
    # @param assets [Array<MediaAsset>]
    # @return [Array<String>] creation_ids in the same order as +assets+
    def create_child_containers(assets)
      assets.each_with_index.map do |asset, index|
        Rails.logger.debug(
          "[Instagram::CarouselPublisher] Creating child container #{index + 1}/#{assets.size} " \
          "for MediaAsset##{asset.id}"
        )

        creation_id = create_container(
          image_url:         resolve_public_url!(asset),
          is_carousel_item:  "true"
        )

        Rails.logger.debug(
          "[Instagram::CarouselPublisher] Waiting for child container #{creation_id} to finish…"
        )
        wait_until_finished!(creation_id)

        creation_id
      end
    end

    # Step 2 – create the parent CAROUSEL container that groups the children.
    #
    # @param child_ids [Array<String>] ordered creation_ids of child containers
    # @param caption   [String, nil]
    # @return [String] parent creation_id
    def create_parent_container(child_ids, caption: nil)
      Rails.logger.debug(
        "[Instagram::CarouselPublisher] Creating parent carousel container " \
        "with #{child_ids.size} children"
      )

      params = {
        media_type: "CAROUSEL",
        children:   child_ids.join(",")
      }
      params[:caption] = caption if caption.present?

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
          Rails.logger.debug("[Instagram::CarouselPublisher] Container #{creation_id} is FINISHED.")
          return
        when "ERROR", "EXPIRED"
          raise Instagram::ApiError,
                "Container #{creation_id} entered terminal status '#{status_code}': #{result["status"]}"
        else
          # IN_PROGRESS or other transient states — keep polling
          Rails.logger.debug(
            "[Instagram::CarouselPublisher] Container #{creation_id} status: #{status_code}. " \
            "Retrying in #{POLL_INTERVAL_SECONDS}s…"
          )
        end

        if Time.current >= deadline
          raise Instagram::ContainerTimeoutError,
                "Container #{creation_id} did not finish within #{timeout}s"
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

    # Return the public HTTPS URL stored in the asset's raw_metadata["public_url"].
    def resolve_public_url!(asset)
      metadata = asset.raw_metadata
      metadata = JSON.parse(metadata) if metadata.is_a?(String)
      url = metadata&.dig("public_url")

      if url.blank?
        raise Instagram::ApiError,
              "MediaAsset #{asset.id} has no public URL. " \
              "Upload the file to a public CDN before publishing."
      end

      url
    end
  end
end
