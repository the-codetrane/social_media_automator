# frozen_string_literal: true

module Api
  class MediaAssetsController < BaseController
    # GET /api/media_assets
    # Optional filters: ?media_type=image&status=processed
    def index
      assets = MediaAsset.all
      assets = assets.where(media_type: params[:media_type]) if params[:media_type].present?
      assets = assets.where(status: params[:status]) if params[:status].present?
      assets = assets.order(first_seen_at: :desc)

      render json: assets.map { |a| media_asset_response(a) }
    end

    # GET /api/media_assets/:id
    def show
      asset = MediaAsset.find(params[:id])
      render json: media_asset_response(asset)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Media asset not found" }, status: :not_found
    end

    private

    def media_asset_response(asset)
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
        first_seen_at: asset.first_seen_at&.iso8601,
        created_at: asset.created_at.iso8601,
        updated_at: asset.updated_at.iso8601
      }
    end
  end
end
