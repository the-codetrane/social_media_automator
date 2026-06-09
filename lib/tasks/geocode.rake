# frozen_string_literal: true

namespace :geocode do
  desc "Extract GPS from EXIF and reverse geocode media assets lacking location data"
  task media_assets: :environment do
    # Phase 1: JPEG images without coordinates — extract from EXIF, then reverse geocode
    exif_candidates = MediaAsset.images
      .where(latitude: nil)
      .joins(:file_attachment)

    puts "Phase 1: EXIF extraction (#{exif_candidates.count} images without coordinates)"

    exif_geocoded = 0
    exif_skipped  = 0

    exif_candidates.find_each do |asset|
      next unless asset.mime_type&.include?("jpeg")

      before = asset.latitude
      asset.valid?

      if asset.latitude.present?
        asset.save!
        exif_geocoded += 1
        puts "  [#{asset.id}] #{asset.external_name} → #{asset.latitude}, #{asset.longitude} (#{asset.city}, #{asset.country})"
        sleep 1  # Nominatim rate limit: 1 req/sec
      else
        exif_skipped += 1
      end
    end

    puts "  Done: #{exif_geocoded} geocoded, #{exif_skipped} skipped (no GPS in EXIF)"

    # Phase 2: Assets with coordinates but no address — reverse geocode only
    address_candidates = MediaAsset.where.not(latitude: nil).where(address: nil)

    puts "\nPhase 2: Reverse geocoding (#{address_candidates.count} assets with coordinates but no address)"

    address_geocoded = 0

    address_candidates.find_each do |asset|
      asset.reverse_geocode
      asset.save!
      address_geocoded += 1
      puts "  [#{asset.id}] #{asset.external_name} → #{asset.address}"
      sleep 1  # Nominatim rate limit: 1 req/sec
    end

    puts "  Done: #{address_geocoded} reverse geocoded"

    puts "\nFinished. Total geocoded: #{exif_geocoded + address_geocoded}"
  end
end
