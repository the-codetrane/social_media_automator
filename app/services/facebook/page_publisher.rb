# frozen_string_literal: true

module Facebook
  # Publishes a PlannedPost to a Facebook Page feed via the Meta Pages API.
  #
  # Requires the user to have completed Instagram OAuth with pages_manage_posts
  # permission and have instagram_page_id set.
  #
  # The shape is chosen from the post itself:
  #   * story    — platform_payload["post_type"] == "story"; handed to
  #                Facebook::StoriesPublisher, which uses a different API
  #   * carousel — platform_payload["carousel_asset_ids"] lists 2+ image assets
  #   * video    — the primary media_asset is a video
  #   * photo    — the primary media_asset is an image
  #   * text     — no usable media asset
  #
  # Usage:
  #   publisher = Facebook::PagePublisher.new(user)
  #   publisher.publish(planned_post)
  class PagePublisher
    # A Page feed post accepts at most 10 attached photos.
    MAX_CAROUSEL_ITEMS = 10
    # Below this an "attached_media" post is just a single photo post.
    MIN_CAROUSEL_ITEMS = 2

    # @param user [User] must have instagram_page_id + instagram_access_token set
    def initialize(user)
      @user    = user
      @page_id = Facebook::PageToken.page_id_for!(user)
    end

    # @param planned_post [PlannedPost]
    # @return [String] the Facebook post ID
    def publish(planned_post)
      # Stories are not a feed post with a flag — they have their own endpoints
      # and their own bookkeeping, so they leave here entirely.
      return Facebook::StoriesPublisher.new(@user).publish(planned_post) if planned_post.story?

      page_token       = fetch_page_access_token
      post_id, payload = post_content(planned_post, page_token)

      attributes = {
        status:           :published,
        external_post_id: post_id,
        published_at:     Time.current
      }
      attributes[:platform_payload] = planned_post.platform_payload.to_h.merge(payload) if payload.present?

      planned_post.update!(attributes)

      post_id
    end

    private

    # Exchange the stored user token for a Page access token.
    def fetch_page_access_token
      Facebook::PageToken.fetch(@user, @page_id)
    end

    # @return [Array(String, Hash)] the Facebook post ID and any extra
    #   platform_payload keys to record on the post.
    def post_content(planned_post, page_token)
      client  = Instagram::ApiClient.new(@user, access_token: page_token)
      caption = build_caption(planned_post)
      assets  = carousel_assets(planned_post)

      return publish_carousel(client, assets, caption) if assets.size >= MIN_CAROUSEL_ITEMS

      asset = assets.first || planned_post.media_asset

      if asset&.video?
        result = client.post("#{@page_id}/videos", file_url: resolve_public_url!(asset), description: caption)
        [ result["id"], {} ]
      elsif asset&.image?
        result = client.post("#{@page_id}/photos", url: resolve_public_url!(asset), message: caption)
        [ result["post_id"] || result["id"], {} ]
      else
        result = client.post("#{@page_id}/feed", message: caption)
        [ result["id"], {} ]
      end
    end

    # Ordered assets for a multi-photo post, or [] when this is not a carousel.
    #
    # Missing MediaAsset rows are skipped rather than raising: a carousel that
    # lost one of its images should still publish the rest.
    def carousel_assets(planned_post)
      ids = planned_post.platform_payload&.dig("carousel_asset_ids")
      return [] if ids.blank?

      assets = MediaAsset.where(id: ids).index_by(&:id)
      ids.filter_map { |id| assets[id.to_i] }
    end

    # A Page feed post carries multiple photos by attaching unpublished photo
    # IDs, which is the only multi-item format the Pages API offers:
    #   1. POST /{page-id}/photos with published=false → one media_fbid per image
    #   2. POST /{page-id}/feed with attached_media[N] referencing those IDs
    #
    # Video is not attachable this way, so a mixed carousel is rejected up front
    # rather than silently dropping the video.
    def publish_carousel(client, assets, caption)
      validate_carousel!(assets)

      media_fbids = assets.each_with_index.map do |asset, index|
        Rails.logger.debug(
          "[Facebook::PagePublisher] Uploading unpublished photo #{index + 1}/#{assets.size} " \
          "for MediaAsset##{asset.id}"
        )

        result = client.post(
          "#{@page_id}/photos",
          url:       resolve_public_url!(asset),
          published: "false",
          temporary: "true"
        )

        result["id"] ||
          raise(Instagram::ApiError, "No photo ID returned for MediaAsset##{asset.id}: #{result.inspect}")
      end

      params = { message: caption }
      media_fbids.each_with_index do |fbid, index|
        params["attached_media[#{index}]"] = { media_fbid: fbid }.to_json
      end

      result  = client.post("#{@page_id}/feed", params)
      post_id = result["id"] ||
        raise(Instagram::ApiError, "No post ID returned for carousel: #{result.inspect}")

      [ post_id, { "carousel_item_count" => assets.size, "carousel_media_fbids" => media_fbids } ]
    end

    def validate_carousel!(assets)
      if assets.size > MAX_CAROUSEL_ITEMS
        raise Instagram::ApiError,
              "Facebook carousels support at most #{MAX_CAROUSEL_ITEMS} photos (#{assets.size} provided)."
      end

      unsupported = assets.reject(&:image?)
      if unsupported.any?
        ids = unsupported.map { |asset| "#{asset.id} (#{asset.media_type})" }.join(", ")
        raise Instagram::ApiError,
              "Facebook carousels accept images only — the Pages API cannot attach video to a " \
              "multi-item feed post. Unsupported asset IDs: #{ids}."
      end
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

    def build_caption(planned_post)
      [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?).join("\n\n")
    end
  end
end
