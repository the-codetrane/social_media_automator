# frozen_string_literal: true

module Api
  class MediaAssetFromUrlService
    SUPPORTED_IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .heic].freeze
    SUPPORTED_VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .webm .m4v].freeze
    SUPPORTED_AUDIO_EXTENSIONS = %w[.mp3 .wav .m4a .aac .flac].freeze

    attr_reader :url, :media_asset, :error

    def initialize(url)
      @url = url
      @media_asset = nil
      @error = nil
    end

    def call
      return false unless valid_url?

      # Check if media asset already exists with this URL
      existing_asset = find_existing_asset
      if existing_asset
        @media_asset = existing_asset
        return true
      end

      # Create new media asset
      create_media_asset
    end

    def success?
      @error.nil? && @media_asset.present?
    end

    private

    def valid_url?
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        @error = "Invalid URL format"
        return false
      end
      true
    rescue URI::InvalidURIError
      @error = "Invalid URL format"
      false
    end

    # The same Spaces object can arrive as many different URL strings (CDN vs
    # origin host, raw vs percent-encoded), so match on the object key first.
    # external_id still catches non-Spaces URLs and pre-storage_key rows.
    def find_existing_asset
      (storage_key && MediaAsset.find_by(storage_key: storage_key)) ||
        MediaAsset.find_by(external_id: generate_external_id)
    end

    def storage_key
      return @storage_key if defined?(@storage_key)

      @storage_key = MediaAsset.storage_key_for_url(url)
    end

    def create_media_asset
      @media_asset = MediaAsset.new(
        external_id: generate_external_id,
        external_name: extract_filename,
        media_type: detect_media_type,
        status: :discovered,
        first_seen_at: Time.current,
        storage_key: storage_key,
        raw_metadata: { public_url: url, source: "api" }.to_json
      )

      saved = begin
        @media_asset.save
      rescue ActiveRecord::RecordNotUnique
        false
      end
      return true if saved

      # Lost a race with a concurrent import of the same object.
      if (existing = find_existing_asset)
        @media_asset = existing
        return true
      end

      @error = @media_asset.errors.full_messages.join(", ")
      false
    end

    def generate_external_id
      # Hash the Spaces key when there is one, so every spelling of the same
      # object's URL yields the same id; fall back to the URL otherwise.
      "api_#{Digest::SHA256.hexdigest(storage_key || url)[0, 16]}"
    end

    def extract_filename
      uri = URI.parse(url)
      File.basename(uri.path.to_s)
    rescue StandardError
      "unknown"
    end

    def detect_media_type
      uri = URI.parse(url)
      extension = File.extname(uri.path.to_s).downcase

      if SUPPORTED_IMAGE_EXTENSIONS.include?(extension)
        :image
      elsif SUPPORTED_VIDEO_EXTENSIONS.include?(extension)
        :video
      elsif SUPPORTED_AUDIO_EXTENSIONS.include?(extension)
        :audio
      else
        :video
      end
    rescue StandardError
      :video
    end
  end
end
