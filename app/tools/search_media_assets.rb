class SearchMediaAssets < RubyLLM::Tool
  description "Search MediaAsset database records by name, geocoding status, media type, or processing status. " \
              "Use this to find the asset to attach to a planned post. " \
              "Returns id, external_name, media_type, status, and location fields for each match."

  param :name,
    type: :string,
    desc: "Case-insensitive substring to match against external_name.",
    required: false

  param :geocoded,
    type: :boolean,
    desc: "true = only assets with coordinates, false = only assets without. Omit to return both.",
    required: false

  param :media_type,
    type: :string,
    desc: "Filter by type: 'image', 'video', or 'audio'. Omit for all.",
    required: false

  param :status,
    type: :string,
    desc: "Filter by status: 'discovered', 'processed', 'failed', or 'archived'. Omit for all.",
    required: false

  param :limit,
    type: :integer,
    desc: "Max records to return (default: 50, max: 200).",
    required: false

  def execute(name: nil, geocoded: nil, media_type: nil, status: nil, limit: 50)
    limit = [ [ limit.to_i, 1 ].max, 200 ].min

    assets = build_scope(name, geocoded, media_type, status).limit(limit)

    {
      total: assets.size,
      assets: assets.map { |a| serialize(a) }
    }
  end

  private

  def build_scope(name, geocoded, media_type, status)
    scope = MediaAsset.all

    if name.present?
      escaped = name.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
      scope = scope.where("LOWER(external_name) LIKE ? ESCAPE '\\'", "%#{escaped.downcase}%")
    end

    unless geocoded.nil?
      scope = geocoded ? scope.where.not(latitude: nil) : scope.where(latitude: nil)
    end

    scope = scope.where(media_type: media_type) if media_type.present?
    scope = scope.where(status: status)         if status.present?

    scope.order(created_at: :desc)
  end

  def serialize(asset)
    {
      id:            asset.id,
      external_name: asset.external_name,
      media_type:    asset.media_type,
      status:        asset.status,
      geocoded:      asset.latitude.present?,
      city:          asset.city,
      state:         asset.state,
      latitude:      asset.latitude,
      longitude:     asset.longitude
    }
  end
end
