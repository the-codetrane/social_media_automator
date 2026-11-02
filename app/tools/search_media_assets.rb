class SearchMediaAssets < RubyLLM::Tool
  description "Search MediaAsset database records by name, geocoding status, media type, processing status, " \
              "or availability. Use this to find the asset to attach to a planned post. By default only " \
              "available assets are returned — not archived, never published, and not on a scheduled post — " \
              "so the same media is not posted twice. " \
              "Returns id, external_name, media_type, status, availability, and location fields for each match."

  parameter :name,
    type: :string,
    description: "Case-insensitive substring to match against external_name.",
    required: false

  parameter :geocoded,
    type: :boolean,
    description: "true = only assets with coordinates, false = only assets without. Omit to return both.",
    required: false

  parameter :media_type,
    type: :string,
    description: "Filter by type: 'image', 'video', or 'audio'. Omit for all.",
    required: false

  parameter :status,
    type: :string,
    description: "Filter by processing status: 'discovered', 'processed', or 'failed'. Omit for all.",
    required: false

  parameter :availability,
    type: :string,
    description: "'available' (default): unused assets only. 'reserved': on a scheduled post. " \
                 "'published': already posted. 'archived': retired by the user. 'all': no filter. " \
                 "Only search beyond 'available' when the user explicitly wants to reuse media.",
    required: false

  parameter :limit,
    type: :integer,
    description: "Max records to return (default: 50, max: 200).",
    required: false

  def execute(name: nil, geocoded: nil, media_type: nil, status: nil, availability: nil, limit: 50)
    limit = [ [ limit.to_i, 1 ].max, 200 ].min
    availability = availability.presence || "available"
    availability = "archived" if status == "archived"

    assets = build_scope(name, geocoded, media_type, status, availability).limit(limit)
    reserved_ids = MediaAsset.reserved_ids

    {
      total: assets.size,
      assets: assets.map { |a| serialize(a, reserved_ids) }
    }
  end

  private

  def build_scope(name, geocoded, media_type, status, availability)
    scope = MediaAsset.with_availability(availability)

    if name.present?
      escaped = name.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
      scope = scope.where("LOWER(external_name) LIKE ? ESCAPE '\\'", "%#{escaped.downcase}%")
    end

    unless geocoded.nil?
      scope = geocoded ? scope.where.not(latitude: nil) : scope.where(latitude: nil)
    end

    scope = scope.where(media_type: media_type) if media_type.present?
    scope = scope.where(status: status)         if status.present? && status != "archived"

    scope.order(created_at: :desc)
  end

  def serialize(asset, reserved_ids)
    {
      id:            asset.id,
      external_name: asset.external_name,
      media_type:    asset.media_type,
      status:        asset.status,
      availability:  asset.availability(reserved_ids: reserved_ids),
      published_at:  asset.published_at&.iso8601,
      geocoded:      asset.latitude.present?,
      city:          asset.city,
      state:         asset.state,
      latitude:      asset.latitude,
      longitude:     asset.longitude
    }
  end
end
