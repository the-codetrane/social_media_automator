require "exifr/jpeg"
require "net/http"

class EnrichMediaAssets < RubyLLM::Tool
  description "Enrich unprocessed media assets with venue GPS data (extracted from JPEG EXIF) " \
              "and identified people (via vision AI). Marks enriched assets as processed. " \
              "Run this after sync_media_assets_from_spaces to populate location and face data " \
              "before creating variety posts."

  param :user_id,
    type: :integer,
    desc: "User ID — used to load their registered known people for face identification"

  param :asset_ids,
    type: :array,
    desc: "Specific MediaAsset IDs to enrich. Leave blank to process all unprocessed image assets.",
    required: false

  param :limit,
    type: :integer,
    desc: "Max assets to process in one call (default: 20, max: 100). Vision API calls are slow.",
    required: false

  param :force_refresh,
    type: :boolean,
    desc: "Re-run face identification even if cached results exist (default: false)",
    required: false

  def execute(user_id:, asset_ids: nil, limit: 20, force_refresh: false)
    limit = [ [ limit.to_i, 1 ].max, 100 ].min

    assets = if asset_ids.present?
      MediaAsset.where(id: Array(asset_ids).map(&:to_i))
    else
      MediaAsset.images
        .where(status: [ :discovered, :failed ])
        .or(MediaAsset.images.where(identified_people: nil))
        .distinct
        .limit(limit)
    end

    known_people = KnownPerson.where(user_id: user_id).to_a
    face_service = known_people.any? ? Vision::FaceIdentifierService.new(known_people) : nil

    results = { processed: 0, gps_extracted: 0, faces_identified: 0, skipped: 0, errors: [] }

    assets.each do |asset|
      unless asset.public_url?
        results[:skipped] += 1
        next
      end

      # Extract GPS from JPEG EXIF (only if not already geocoded)
      if asset.image? && asset.latitude.nil?
        gps = extract_gps_from_url(asset.public_url)
        if gps
          asset.latitude  = gps[:latitude]
          asset.longitude = gps[:longitude]
          results[:gps_extracted] += 1
        end
      end

      # Face identification
      if asset.image? && face_service && (asset.identified_people.nil? || force_refresh)
        begin
          identified = face_service.call(asset.public_url)
          if identified.is_a?(Array)
            asset.identified_people    = identified
            asset.identified_people_at = Time.current
            results[:faces_identified] += 1
          else
            results[:errors] << "Asset #{asset.id} face ID: #{identified[:error]}"
          end
        rescue => e
          results[:errors] << "Asset #{asset.id} face ID: #{e.message}"
        end
      end

      asset.status = :processed
      if asset.save
        results[:processed] += 1
      else
        results[:errors] << "Asset #{asset.id} save failed: #{asset.errors.full_messages.join(', ')}"
      end
    end

    results[:errors] = results[:errors].first(10)
    results
  end

  private

  def extract_gps_from_url(url)
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 15) do |http|
      http.get(uri.request_uri)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    Tempfile.create([ "enrich_gps", ".jpg" ]) do |tmp|
      tmp.binmode
      tmp.write(response.body)
      tmp.flush
      exif = EXIFR::JPEG.new(tmp.path)
      return nil unless exif&.gps
      { latitude: exif.gps.latitude, longitude: exif.gps.longitude }
    end
  rescue EXIFR::MalformedJPEG, EXIFR::MalformedTIFF
    nil
  rescue URI::InvalidURIError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    Rails.logger.warn("EnrichMediaAssets GPS extraction failed for #{url}: #{e.message}")
    nil
  end
end
