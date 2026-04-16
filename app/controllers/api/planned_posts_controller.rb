            params: post_params.except(:user_id, :media_url),
            errors: [ "Media asset error: #{service.error}" ]
      # If media_asset_id is provided, use it directly
            index: index,
            params: post_params.except(:user_id, :media_url, :media_urls),
            errors: planned_post.errors.full_messages
          }
        end
      end

      status = results[:errors].any? ? :multi_status : :created
            params: post_params.except(:user_id, :media_url),
    end

    private

    # Resolves media assets from various input formats.
    # Supports: media_asset_id, media_url (single), media_urls (array for carousels)
    #
    def resolve_media_asset_id(post_params)
      # If media_asset_id is provided, use it directly
      if post_params[:media_url].present?
        service = MediaAssetFromUrlService.new(post_params[:media_url])
        if service.call
          id = service.media_asset.id
          return { primary_id: id, all_ids: [ id ] }
        else
          render json: { errors: [ "Media asset error: #{service.error}" ] }, status: :unprocessable_entity
          return nil
        end
      end

      # Neither provided - will fail validation
      { primary_id: nil, all_ids: [] }
    end

    # Bulk version of resolve_media_assets that collects errors instead of rendering.
    #
    # @param post_params [ActionController::Parameters]
    # @param results [Hash] the bulk results hash to append errors to
    # @param index [Integer] the index of this post in the bulk request
    # @return [Hash, nil] { primary_id: Integer, all_ids: Array<Integer> } or nil on error
    def resolve_media_assets_for_bulk(post_params, results, index)
      # Priority 1: Array of URLs for carousel posts
      if post_params[:media_urls].present?
        urls = Array(post_params[:media_urls])
        asset_ids = []

        urls.each_with_index do |url, idx|
          service = MediaAssetFromUrlService.new(url)
          if service.call
            asset_ids << service.media_asset.id
          else
            results[:errors] << {
              index: index,
              params: post_params.except(:user_id, :media_url, :media_urls),
              errors: [ "Media asset error at URL index #{idx}: #{service.error}" ]
            }
            return nil
          end
        end

        return { primary_id: asset_ids.first, all_ids: asset_ids }
      end

      # Priority 2: Single media_asset_id
      if post_params[:media_asset_id].present?
        id = post_params[:media_asset_id]
        return { primary_id: id, all_ids: [ id ] }
      end

      # Priority 3: Single media_url
      if post_params[:media_url].present?
        service = MediaAssetFromUrlService.new(post_params[:media_url])
        if service.call
          id = service.media_asset.id
          return { primary_id: id, all_ids: [ id ] }
        else
          results[:errors] << {
            index: index,
            params: post_params.except(:user_id, :media_url, :media_urls),
            errors: [ "Media asset error: #{service.error}" ]
          }
          return nil
        end
      end

      # Neither provided - will fail validation later
      nil
      { primary_id: nil, all_ids: [] }
    end

    # Merges carousel_asset_ids into platform_payload for multi-asset posts.
    #
    # @param attrs [Hash] the post attributes
    # @param asset_ids [Array<Integer>] ordered list of MediaAsset IDs
    # @return [Hash] updated attributes with carousel_asset_ids in platform_payload
    def merge_carousel_payload(attrs, asset_ids)
      existing_payload = attrs[:platform_payload] || {}
      attrs.merge(
        platform_payload: existing_payload.merge("carousel_asset_ids" => asset_ids)
      )
    end

    def planned_post_params
      params.require(:planned_post).permit(
        :user_id,
        :media_asset_id,
        :media_url,
        :social_template_id,
        :platform,
        :status,
        :caption,
        :hashtags,
        :scheduled_at,
        platform_payload: {}
      ).except(:media_url)
        platform_payload: {},
        media_urls: []
      ).except(:media_url, :media_urls)
    end

    def planned_posts_params
      params.require(:planned_posts).map do |post_params|
        post_params.permit(
          :user_id,
          :media_asset_id,
          :media_url,
          :social_template_id,
          :platform,
          :status,
          :caption,
          :hashtags,
          :scheduled_at,
          platform_payload: {}
          platform_payload: {},
          media_urls: []
        )
      end
    end

    def planned_post_response(planned_post)
      {
        id: planned_post.id,
        user_id: planned_post.user_id,
        media_asset_id: planned_post.media_asset_id,
        social_template_id: planned_post.social_template_id,
        platform: planned_post.platform,
        status: planned_post.status,
        caption: planned_post.caption,
        hashtags: planned_post.hashtags,
        scheduled_at: planned_post.scheduled_at&.iso8601,
        platform_payload: planned_post.platform_payload,
        created_at: planned_post.created_at.iso8601,
        updated_at: planned_post.updated_at.iso8601
      }
    end
  end
end
