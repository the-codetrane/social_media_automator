# frozen_string_literal: true

require "open-uri"

class FetchStaticMapJob < ApplicationJob
  queue_as :default

  def perform(media_asset_id)
    asset = MediaAsset.find(media_asset_id)
    return if asset.static_map_image.attached?
    return unless asset.geocoded?

    maps_key = Rails.application.credentials.dig(:google, :maps_api_key)
    return unless maps_key.present?

    url = "https://maps.googleapis.com/maps/api/staticmap" \
          "?center=#{asset.latitude},#{asset.longitude}" \
          "&zoom=14" \
          "&size=640x320" \
          "&markers=color:red%7C#{asset.latitude},#{asset.longitude}" \
          "&key=#{maps_key}"

    URI.parse(url).open do |image|
      asset.static_map_image.attach(
        io: image,
        filename: "static_map_#{asset.id}.png",
        content_type: "image/png"
      )
    end
  end
end
