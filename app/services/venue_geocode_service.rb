# frozen_string_literal: true

require "cgi"

# Forward-geocodes an address and applies the coordinates to MediaAssets whose
# external_name matches a given venue string. Triggers the model's reverse-geocode
# callback (populates city/state/country/address) and queues FetchStaticMapJob.
#
# Used by:
#   - lib/tasks/geocode.rake (geocode:venue)
#   - EnhanceMediaAssets tool
class VenueGeocodeService
  Result = Data.define(:geocoded, :errors, :latitude, :longitude, :resolved_address)

  def initialize(venue:, address:, force: false)
    @venue   = venue
    @address = address
    @force   = force
  end

  # @return [Result]
  def call
    geo = resolve_geo
    return failure("Could not geocode address: '#{@address}'") unless geo

    geocoded, errors = apply_coordinates(matching_assets, geo.latitude, geo.longitude)

    Result.new(
      geocoded:         geocoded,
      errors:           errors.first(10),
      latitude:         geo.latitude,
      longitude:        geo.longitude,
      resolved_address: geo.address
    )
  end

  private

  def resolve_geo
    geo = Geocoder.search(@address).first
    geo if geo&.latitude && geo&.longitude
  end

  def apply_coordinates(assets, lat, lon)
    geocoded = 0
    errors   = []

    assets.find_each do |asset|
      asset.latitude  = lat
      asset.longitude = lon

      if asset.save
        geocoded += 1
        sleep 1 # Nominatim rate limit: 1 req/sec per reverse_geocode callback
      else
        errors << "Asset #{asset.id}: #{asset.errors.full_messages.join(', ')}"
      end
    end

    [ geocoded, errors ]
  end

  def matching_assets
    encoded = CGI.escape(@venue).gsub("+", "%20")
    scope = MediaAsset.where(
      "LOWER(external_name) LIKE ? OR LOWER(external_name) LIKE ?",
      "%#{@venue.downcase}%",
      "%#{encoded.downcase}%"
    )
    @force ? scope : scope.where(latitude: nil)
  end

  def failure(message)
    Result.new(geocoded: 0, errors: [ message ], latitude: nil, longitude: nil, resolved_address: nil)
  end
end
