# frozen_string_literal: true

module Api
  class MediaAssetsController < BaseController
    ALLOWED_SORT_COLUMNS = %w[first_seen_at created_at file_size external_name published_at].freeze
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    AVAILABILITY_FILTERS = (MediaAsset::AVAILABILITIES + %w[all]).freeze

    # GET /api/media_assets
    # Filters: media_type, status, mime_type, first_seen_at_after, first_seen_at_before
    #          availability=available|reserved|published|archived|all
    #            (default: everything except archived — archived assets are
    #            soft-deleted. "available" = not archived, never published,
    #            not on a scheduled post.)
    # Search:  q (searches external_name, address)
    # Sort:    sort=first_seen_at|created_at|file_size|external_name|published_at, direction=asc|desc
    # Page:    page, per_page (default 50, max 200)
    def index
      assets = availability_scope
      assets = assets.where(media_type: params[:media_type]) if params[:media_type].present?
      assets = assets.where(status: params[:status]) if params[:status].present? && params[:status] != "archived"
      assets = assets.where(mime_type: params[:mime_type]) if params[:mime_type].present?
      assets = assets.where("first_seen_at >= ?", params[:first_seen_at_after]) if params[:first_seen_at_after].present?
      assets = assets.where("first_seen_at <= ?", params[:first_seen_at_before]) if params[:first_seen_at_before].present?

      if params[:q].present?
        term = "%#{params[:q]}%"
        assets = assets.where("external_name LIKE ? OR address LIKE ?", term, term)
      end

      sort_col = ALLOWED_SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "first_seen_at"
      direction = params[:direction]&.downcase == "asc" ? :asc : :desc
      assets = assets.order(sort_col => direction)

      per_page = [ (params[:per_page] || DEFAULT_PER_PAGE).to_i, MAX_PER_PAGE ].min
      per_page = DEFAULT_PER_PAGE if per_page < 1
      page = [ (params[:page] || 1).to_i, 1 ].max
      total = assets.count
      assets = assets.offset((page - 1) * per_page).limit(per_page)

      response.set_header("X-Total-Count", total.to_s)
      response.set_header("X-Page", page.to_s)
      response.set_header("X-Per-Page", per_page.to_s)
      response.set_header("X-Total-Pages", (total.to_f / per_page).ceil.to_s)

      reserved_ids = MediaAsset.reserved_ids
      render json: assets.map { |a| media_asset_response(a, reserved_ids: reserved_ids) }
    end

    # GET /api/media_assets/:id
    def show
      asset = MediaAsset.find(params[:id])
      render json: media_asset_response(asset)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Media asset not found" }, status: :not_found
    end

    # PATCH /api/media_assets/:id/archive
    def archive
      asset = MediaAsset.find(params[:id])
      asset.archive!
      render json: media_asset_response(asset)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Media asset not found" }, status: :not_found
    end

    # PATCH /api/media_assets/:id/unarchive
    def unarchive
      asset = MediaAsset.find(params[:id])
      asset.unarchive!
      render json: media_asset_response(asset)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Media asset not found" }, status: :not_found
    end

    private

    # "status=archived" predates archived_at and is still honoured.
    def availability_scope
      availability = params[:status] == "archived" ? "archived" : params[:availability]

      if AVAILABILITY_FILTERS.include?(availability)
        MediaAsset.with_availability(availability)
      else
        MediaAsset.active
      end
    end

    def media_asset_response(asset, reserved_ids: nil)
      {
        id: asset.id,
        external_id: asset.external_id,
        external_name: asset.external_name,
        media_type: asset.media_type,
        status: asset.status,
        public_url: asset.public_url,
        width: asset.width,
        height: asset.height,
        file_size: asset.file_size,
        duration_seconds: asset.duration_seconds,
        mime_type: asset.mime_type,
        availability: asset.availability(reserved_ids: reserved_ids),
        archived_at: asset.archived_at&.iso8601,
        published_at: asset.published_at&.iso8601,
        first_seen_at: asset.first_seen_at&.iso8601,
        created_at: asset.created_at.iso8601,
        updated_at: asset.updated_at.iso8601
      }
    end
  end
end
