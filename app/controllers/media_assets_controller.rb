# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  before_action :set_media_asset, only: %i[show edit update]

  def index
    @media_assets = MediaAsset.order(created_at: :desc)
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
