# frozen_string_literal: true

require "open-uri"
require "cgi"

namespace :geocode do
  desc "Extract GPS from EXIF and reverse geocode media assets lacking location data"
  task media_assets: :environment do
    # Phase 1: JPEG images without coordinates — extract from EXIF, then reverse geocode.
    # Handles both ActiveStorage-attached files and legacy records with raw_metadata public_url.
    exif_candidates = MediaAsset.images.where(latitude: nil)

    puts "Phase 1: EXIF extraction (#{exif_candidates.count} images without coordinates)"

    exif_geocoded = 0
    exif_skipped  = 0

    exif_candidates.find_each do |asset|
      next unless asset.mime_type&.include?("jpeg")

      if asset.file.attached?
        asset.valid?  # triggers before_validation :extract_gps_from_exif
      else
        url = asset.public_url
        unless url.present?
          exif_skipped += 1
          next
        end

        begin
          URI.parse(url).open do |io|
            Tempfile.create([ "geocode", ".jpg" ]) do |tmp|
              tmp.binmode
              tmp.write(io.read)
              tmp.flush
              exif = EXIFR::JPEG.new(tmp.path)
              if exif&.gps
                asset.latitude  = exif.gps.latitude
                asset.longitude = exif.gps.longitude
              end
            end
          end
        rescue => e
          puts "  [#{asset.id}] error: #{e.message}"
          exif_skipped += 1
          next
        end
      end

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

  desc "Forward geocode media assets whose external_name mentions VENUE using ADDRESS (FORCE=true to overwrite existing coordinates)"
  task venue: :environment do
    venue   = ENV["VENUE"].presence   || abort("Usage: bin/rails geocode:venue VENUE='...' ADDRESS='...'")
    address = ENV["ADDRESS"].presence || abort("Usage: bin/rails geocode:venue VENUE='...' ADDRESS='...'")
    force   = ENV["FORCE"] == "true"

    results = Geocoder.search(address)
    abort "Could not geocode address: #{address}" if results.empty?

    geo = results.first
    lat = geo.latitude
    lon = geo.longitude
    puts "Resolved: #{address} → #{lat}, #{lon}"

    encoded_venue = CGI.escape(venue).gsub("+", "%20")
    candidates = MediaAsset.where(
      "LOWER(external_name) LIKE ? OR LOWER(external_name) LIKE ?",
      "%#{venue.downcase}%",
      "%#{encoded_venue.downcase}%"
    )
    candidates = candidates.where(latitude: nil) unless force

    puts "#{candidates.count} asset(s) matching \"#{venue}\"#{force ? "" : " without existing coordinates"}"

    updated = 0
    candidates.find_each do |asset|
      asset.latitude  = lat
      asset.longitude = lon
      asset.save!
      updated += 1
      puts "  [#{asset.id}] #{asset.external_name} → #{asset.city}, #{asset.country}"
      sleep 1  # Nominatim rate limit: 1 req/sec
    end

    puts "\nDone. #{updated} asset(s) geocoded."
  end
end
