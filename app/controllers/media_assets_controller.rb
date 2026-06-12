# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  before_action :set_media_asset, only: %i[show edit update]

  SORT_COLUMNS = %w[external_name media_type status file_size first_seen_at created_at].freeze

  def index
    @query     = params[:q].to_s.strip
    @sort      = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "created_at"
    @direction = params[:direction] == "asc" ? "asc" : "desc"

    scope = MediaAsset.all
    scope = scope.where("external_name LIKE ?", "%#{@query}%") if @query.length >= 3

    @pagy, @media_assets = pagy(scope.order(@sort => @direction))
  end

  def show
  end

  def edit
  end

  def update
    if @media_asset.update(media_asset_params)
      redirect_to @media_asset, notice: "Media asset was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_media_asset
    @media_asset = MediaAsset.find(params[:id])
  end

  def media_asset_params
    params.require(:media_asset).permit(:external_name, :status)
  end
end
