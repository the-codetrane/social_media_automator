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
  Result = Data.define(:geocoded, :skipped, :errors, :latitude, :longitude, :resolved_address)

  def initialize(venue:, address:, force: false)
    @venue   = venue
    @address = address
    @force   = force
  end

  # @return [Result]
  def call
    geo_results = Geocoder.search(@address)
    return failure("Could not geocode address: '#{@address}'") if geo_results.empty?

    geo     = geo_results.first
    lat     = geo.latitude
    lon     = geo.longitude
    return failure("Geocoder returned nil coordinates for: '#{@address}'") if lat.nil? || lon.nil?

    assets = matching_assets
    geocoded = 0
    skipped  = 0
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

    Result.new(
      geocoded:          geocoded,
      skipped:           skipped,
      errors:            errors.first(10),
      latitude:          lat,
      longitude:         lon,
      resolved_address:  geo.address
    )
  end

  private

  def matching_assets
    encoded = CGI.escape(@venue).gsub("+", "%20")
    scope = MediaAsset.where(
      "LOWER(external_name) LIKE ? OR LOWER(external_name) LIKE ?",
      "%#{@venue.downcase}%",
      "%#{encoded.downcase}%"
    )
    scope = scope.where(latitude: nil) unless @force
    scope
  end

  def failure(message)
    Result.new(geocoded: 0, skipped: 0, errors: [ message ], latitude: nil, longitude: nil, resolved_address: nil)
  end
end
