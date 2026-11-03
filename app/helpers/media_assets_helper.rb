# frozen_string_literal: true

module MediaAssetsHelper
  # Half-width of the embedded map's bounding box, in degrees (~550 m),
  # which frames a venue and its surrounding streets.
  OSM_EMBED_SPAN = 0.005

  # URL for an embeddable OpenStreetMap view centred on the point, with a marker.
  # No API key needed.
  def osm_embed_url(latitude, longitude)
    bbox = [
      longitude - OSM_EMBED_SPAN, latitude - OSM_EMBED_SPAN,
      longitude + OSM_EMBED_SPAN, latitude + OSM_EMBED_SPAN
    ].map { |d| d.round(6) }.join(",")

    "https://www.openstreetmap.org/export/embed.html?" +
      { bbox: bbox, layer: "mapnik", marker: "#{latitude},#{longitude}" }.to_query
  end

  # Link to the full OpenStreetMap site at the point.
  def osm_link_url(latitude, longitude)
    "https://www.openstreetmap.org/?mlat=#{latitude}&mlon=#{longitude}#map=17/#{latitude}/#{longitude}"
  end
end
