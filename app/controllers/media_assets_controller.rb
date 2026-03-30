# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  def index
    @media_assets = MediaAsset.includes(:connected_drive).order(created_at: :desc)
  end
end
