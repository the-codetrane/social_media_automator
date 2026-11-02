# frozen_string_literal: true

module Api
  class PlannedPostsController < BaseController
    ALLOWED_SORT_COLUMNS = %w[scheduled_at created_at published_at].freeze
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    before_action :set_planned_post, only: [ :show, :update, :destroy ]

    # GET /api/planned_posts
    # Filters: status, platform, user_id, scheduled_at_after, scheduled_at_before
    # Search:  q (searches caption, hashtags)
    # Sort:    sort=scheduled_at|created_at|published_at, direction=asc|desc
    # Page:    page, per_page (default 50, max 200)
    def index
      posts = PlannedPost.all
      posts = posts.where(status: params[:status]) if params[:status].present?
      posts = posts.where(platform: params[:platform]) if params[:platform].present?
      posts = posts.where(user_id: params[:user_id]) if params[:user_id].present?
      posts = posts.where("scheduled_at >= ?", params[:scheduled_at_after]) if params[:scheduled_at_after].present?
      posts = posts.where("scheduled_at <= ?", params[:scheduled_at_before]) if params[:scheduled_at_before].present?

      if params[:q].present?
        term = "%#{params[:q]}%"
        posts = posts.where("caption LIKE ? OR hashtags LIKE ?", term, term)
      end

      sort_col = ALLOWED_SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "scheduled_at"
      direction = params[:direction]&.downcase == "desc" ? :desc : :asc
      posts = posts.order(sort_col => direction)

      per_page = [ (params[:per_page] || DEFAULT_PER_PAGE).to_i, MAX_PER_PAGE ].min
      per_page = DEFAULT_PER_PAGE if per_page < 1
      page = [ (params[:page] || 1).to_i, 1 ].max
      total = posts.count
      posts = posts.offset((page - 1) * per_page).limit(per_page)

      response.set_header("X-Total-Count", total.to_s)
      response.set_header("X-Page", page.to_s)
      response.set_header("X-Per-Page", per_page.to_s)
      response.set_header("X-Total-Pages", (total.to_f / per_page).ceil.to_s)

      render json: posts.map { |p| planned_post_response(p) }
    end

    # GET /api/planned_posts/:id
    def show
      render json: planned_post_response(@planned_post)
    end

    def create
      resolved = resolve_media_assets(params[:planned_post])
      return if performed?

      post_attrs = planned_post_params.merge(media_asset_id: resolved[:primary_id])
      post_attrs = merge_carousel_payload(post_attrs, resolved[:all_ids]) if resolved[:all_ids].size > 1
      post_attrs = apply_post_type(post_attrs, params.dig(:planned_post, :post_type))

      planned_post = PlannedPost.new(post_attrs)

      if planned_post.save
        render json: planned_post_response_with_warnings(planned_post), status: :created
      else
        render json: { errors: planned_post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def bulk_create
      results = { created: [], errors: [] }

      planned_posts_params.each_with_index do |post_params, index|
        resolved = resolve_media_assets_for_bulk(post_params, results, index)
        next if resolved.nil?

        post_attrs = post_params.except(:media_url, :media_urls, :post_type).merge(media_asset_id: resolved[:primary_id])
        post_attrs = merge_carousel_payload(post_attrs, resolved[:all_ids]) if resolved[:all_ids].size > 1
        post_attrs = apply_post_type(post_attrs, post_params[:post_type])

        planned_post = PlannedPost.new(post_attrs)

        if planned_post.save
          results[:created] << planned_post_response_with_warnings(planned_post)
        else
          results[:errors] << {
            index: index,
            params: post_params.except(:user_id, :media_url, :media_urls),
            errors: planned_post.errors.full_messages
          }
        end
      end

      status = results[:errors].any? ? :multi_status : :created
      render json: results, status: status
    end

    # PATCH /api/planned_posts/:id
    # Accepts media_asset_ids (array of existing IDs), media_urls (array of URLs),
    # or scalar fields (caption, hashtags, scheduled_at, status, platform_payload).
    # media_asset_ids / media_urls set carousel order; first entry becomes primary.
    def update
      attrs = update_post_params.to_h

      if params[:planned_post][:media_asset_ids].present?
        asset_ids = Array(params[:planned_post][:media_asset_ids]).map(&:to_i)
        attrs[:media_asset_id] = asset_ids.first
        attrs[:platform_payload] = (attrs[:platform_payload] || @planned_post.platform_payload || {})
          .merge("carousel_asset_ids" => asset_ids)
      elsif params[:planned_post][:media_urls].present?
        resolved = resolve_media_assets(params[:planned_post])
        return if performed?

        attrs[:media_asset_id] = resolved[:primary_id]
        if resolved[:all_ids].size > 1
          attrs[:platform_payload] = (attrs[:platform_payload] || @planned_post.platform_payload || {})
            .merge("carousel_asset_ids" => resolved[:all_ids])
        end
      end

      attrs = apply_post_type(attrs, params.dig(:planned_post, :post_type), existing: @planned_post.platform_payload)

      if @planned_post.update(attrs)
        render json: planned_post_response_with_warnings(@planned_post)
      else
        render json: { errors: @planned_post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/planned_posts/:id
    def destroy
      @planned_post.destroy!
      head :no_content
    end

    private

    def set_planned_post
      @planned_post = PlannedPost.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Planned post not found" }, status: :not_found
    end

    # Resolves media assets from various input formats.
    # Supports: media_asset_id, media_url (single), media_urls (array for carousels)
    #
    # @param post_params [ActionController::Parameters]
    # @return [Hash] { primary_id: Integer, all_ids: Array<Integer> } or renders error
    def resolve_media_assets(post_params)
      # Priority 1: Array of URLs for carousel posts
      if post_params[:media_urls].present?
        urls = Array(post_params[:media_urls])
        asset_ids = []

        urls.each_with_index do |url, idx|
          service = MediaAssetFromUrlService.new(url)
          if service.call
            asset_ids << service.media_asset.id
          else
            render json: { errors: [ "Media asset error at index #{idx}: #{service.error}" ] }, status: :unprocessable_entity
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

    # Records an explicit post_type inside platform_payload, which is where
    # Instagram::MediaPublisher looks for it.  Exposing it as a top-level
    # attribute saves API clients from having to know that, and from having to
    # resend the rest of the payload just to set one key.
    #
    # Only "story" is stored: "single" and "carousel" are inferred from the
    # assets, so recording them would let a stale value contradict the media.
    #
    # @param attrs [Hash, ActionController::Parameters]
    # @param post_type [String, nil]
    # @param existing [Hash, nil] the post's current payload, for updates
    # @return [Hash, ActionController::Parameters] attrs with platform_payload set
    def apply_post_type(attrs, post_type, existing: nil)
      return attrs if post_type.blank?

      payload = attrs[:platform_payload] || existing || {}
      payload = payload.to_h

      attrs.merge(
        platform_payload: post_type.to_s == "story" ? payload.merge("post_type" => "story") : payload.except("post_type")
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
        :post_type,
        platform_payload: {},
        media_urls: []
      ).except(:media_url, :media_urls, :post_type)
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
          :post_type,
          platform_payload: {},
          media_urls: []
        )
      end
    end

    def update_post_params
      params.require(:planned_post).permit(
        :media_asset_id,
        :social_template_id,
        :platform,
        :status,
        :caption,
        :hashtags,
        :scheduled_at,
        :post_type,
        platform_payload: {},
        media_urls: [],
        media_asset_ids: []
      ).except(:media_urls, :media_asset_ids, :post_type)
    end

    # Reusing an archived, published or already-scheduled asset is allowed but
    # flagged, so API callers can catch accidental duplicates.
    def planned_post_response_with_warnings(planned_post)
      planned_post_response(planned_post).merge(warnings: planned_post.media_asset_reuse_warnings)
    end

    def planned_post_response(planned_post)
      carousel_ids = planned_post.platform_payload&.dig("carousel_asset_ids")
      {
        id: planned_post.id,
        user_id: planned_post.user_id,
        media_asset_id: planned_post.media_asset_id,
        carousel_asset_ids: carousel_ids || [ planned_post.media_asset_id ],
        social_template_id: planned_post.social_template_id,
        platform: planned_post.platform,
        post_type: planned_post.post_type,
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
