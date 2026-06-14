class EnhanceMediaAssets < RubyLLM::Tool
  description "Rename and/or geocode MediaAssets. " \
              "Use search_term to filter assets by name (partial match on external_name). " \
              "Pass new_name to rename all matched assets. " \
              "Pass venue + address to geocode: venue is the name used to find matching assets " \
              "(e.g. 'The Fillmore'), address is what gets forward-geocoded (e.g. '1805 Geary Blvd, San Francisco'). " \
              "Geocoding sets lat/lon on matched assets, which triggers reverse geocoding to populate " \
              "city/state/country/address and queues a static map fetch. " \
              "Pass asset_ids to target specific records instead of (or alongside) a name search."

  param :asset_ids,
    type: :array,
    desc: "Specific MediaAsset IDs to enhance. If omitted, search_term or venue is required.",
    required: false

  param :search_term,
    type: :string,
    desc: "Case-insensitive substring to match agai nst external_name for renaming.",
    required: false

  param :new_name,
    type: :string,
    desc: "Rename matched assets to this value. Leave blank to skip renaming.",
    required: false

  param :venue,
    type: :string,
    desc: "Venue name used to find matching assets by external_name (e.g. 'The Fillmore'). " \
          "Required when geocoding. Also used as the address if address is omitted.",
    required: false

  param :address,
    type: :string,
    desc: "Address or place name to forward-geocode (e.g. '1805 Geary Blvd, San Francisco'). " \
          "Defaults to venue if omitted.",
    required: false

  param :force_geocode,
    type: :boolean,
    desc: "Re-geocode assets that already have coordinates (default: false).",
    required: false

  def execute(asset_ids: nil, search_term: nil, new_name: nil, venue: nil, address: nil, force_geocode: false)
    geocoding = venue.present?
    renaming  = new_name.present? && (asset_ids.present? || search_term.present?)

    unless geocoding || renaming
      return { error: "Nothing to do. For renaming: provide search_term/asset_ids + new_name. " \
                      "For geocoding: provide venue (+ optional address)." }
    end

    results = {}

    if renaming
      results[:rename] = rename_assets(asset_ids, search_term, new_name)
    end

    if geocoding
      geocode_address = address.presence || venue
      svc = VenueGeocodeService.new(venue: venue, address: geocode_address, force: force_geocode)
      r   = svc.call
      results[:geocode] = {
        geocoded:         r.geocoded,
        errors:           r.errors,
        latitude:         r.latitude,
        longitude:        r.longitude,
        resolved_address: r.resolved_address
      }
    end

    results
  end

  private

  def rename_assets(asset_ids, search_term, new_name)
    assets = load_assets(asset_ids, search_term)
    return { error: "No assets found matching the given criteria." } if assets.empty?

    updated = 0
    errors  = []

    assets.each do |asset|
      if asset.update(external_name: new_name)
        updated += 1
      else
        errors << "Asset #{asset.id}: #{asset.errors.full_messages.join(', ')}"
      end
    end

    { updated: updated, asset_ids: assets.map(&:id), errors: errors.first(10) }
  end

  def load_assets(asset_ids, search_term)
    scope = MediaAsset.all
    scope = scope.where(id: Array(asset_ids).map(&:to_i).reject(&:zero?)) if asset_ids.present?
    if search_term.present?
      escaped = search_term.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
      scope = scope.where("LOWER(external_name) LIKE ? ESCAPE '\\'", "%#{escaped.downcase}%")
    end
    scope.to_a
  end
end
