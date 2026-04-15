# frozen_string_literal: true

module Api
  class MediaAssetFromUrlService
    SUPPORTED_IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .heic].freeze
    SUPPORTED_VIDEO_EXTENSIONS = %w[.mp4 .mov .avi .webm .m4v].freeze

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

    def find_existing_asset
      # Look for existing asset by external_id (URL hash) or by URL in raw_metadata
      external_id = generate_external_id
      MediaAsset.find_by(external_id: external_id)
    end

    def create_media_asset
      @media_asset = MediaAsset.new(
        external_id: generate_external_id,
        external_name: extract_filename,
        media_type: detect_media_type,
        status: :discovered,
        first_seen_at: Time.current,
        raw_metadata: { public_url: url, source: "api" }.to_json
      )

      unless @media_asset.save
        @error = @media_asset.errors.full_messages.join(", ")
        return false
      end

      true
    end

    def generate_external_id
      # Use a hash of the URL as the external_id to ensure uniqueness
      "api_#{Digest::SHA256.hexdigest(url)[0, 16]}"
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
      else
        # Default to video for DigitalOcean Spaces content (common use case)
        :video
      end
    rescue StandardError
      :video
    end
  end
end
