# frozen_string_literal: true

require "open-uri"
require "tempfile"

module YouTube
  # Publishes a single video (or Short) to YouTube via the Data API v3.
  #
  # A video is treated as a YouTube Short when the MediaAsset's duration_seconds
  # is present and under 60 seconds. Shorts have `#Shorts` appended to both the
  # title and description to ensure correct classification.
  #
  # The YouTube upload flow differs from Instagram's container/poll pattern.
  # The Data API v3 performs a single resumable multipart upload:
  #   1. Download the video from its public URL to a local temp file
  #   2. POST /upload/youtube/v3/videos with metadata + file stream
  #   3. Response contains the new video ID
  #
  # Optional platform_payload keys:
  #   "privacy_status" – "public" (default), "unlisted", or "private"
  #   "category_id"    – YouTube category ID string (default: "22" People & Blogs)
  #   "tags"           – Array of keyword tags
  #
  # Usage:
  #   publisher = YouTube::VideoPublisher.new(user)
  #   video_id  = publisher.publish(planned_post)
  class VideoPublisher
    SHORT_MAX_DURATION_SECONDS = 60
    DEFAULT_PRIVACY_STATUS     = "public"
    DEFAULT_CATEGORY_ID        = "22"   # People & Blogs
    MAX_TITLE_LENGTH           = 100

    # @param user [User]
    def initialize(user)
      @user   = user
      @client = YouTube::ApiClient.new
    end

    # Publish the planned post's video to YouTube.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the YouTube video ID
    # @raise [ArgumentError]          when the asset is not a video or has no public URL
    # @raise [YouTube::ApiError]      on API failures
    # @raise [YouTube::RateLimitError] when the daily upload quota is exhausted
    def publish(planned_post)
      asset   = planned_post.media_asset
      payload = planned_post.platform_payload.to_h

      validate_video_asset!(asset)

      short       = short?(asset)
      title       = build_title(planned_post, short:)
      description = build_description(planned_post, short:)
      privacy     = payload.fetch("privacy_status", DEFAULT_PRIVACY_STATUS)
      category    = payload.fetch("category_id", DEFAULT_CATEGORY_ID)
      tags        = payload["tags"].presence

      video_resource = build_video_resource(title, description, privacy, category, tags)
      video_id       = upload!(asset, video_resource)

      planned_post.update!(
        status:           :published,
        external_post_id: video_id,
        published_at:     Time.current,
        platform_payload: payload.merge(
          "youtube_video_id" => video_id,
          "short"            => short,
          "privacy_status"   => privacy
        )
      )

      video_id
    rescue YouTube::Error
      planned_post.update!(status: :failed)
      raise
    end

    private

    def validate_video_asset!(asset)
      unless asset.video?
        raise ArgumentError,
              "YouTube::VideoPublisher requires a video MediaAsset " \
              "(got media_type=#{asset.media_type} for MediaAsset##{asset.id})"
      end

      unless asset.public_url?
        raise YouTube::ApiError,
              "MediaAsset #{asset.id} has no public URL. " \
              "Attach a file via ActiveStorage or set raw_metadata[\"public_url\"]."
      end
    end

    def short?(asset)
      asset.duration_seconds.present? && asset.duration_seconds < SHORT_MAX_DURATION_SECONDS
    end

    def build_title(planned_post, short:)
      first_line = planned_post.caption.to_s.split("\n").first.to_s.strip
      first_line = "YouTube Video" if first_line.blank?

      if short
        first_line.truncate(MAX_TITLE_LENGTH - " #Shorts".length, omission: "…") + " #Shorts"
      else
        first_line.truncate(MAX_TITLE_LENGTH, omission: "…")
      end
    end

    def build_description(planned_post, short:)
      parts = [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?)
      parts << "#Shorts" if short
      parts.join("\n\n")
    end

    def build_video_resource(title, description, privacy, category, tags)
      Google::Apis::YoutubeV3::Video.new(
        snippet: Google::Apis::YoutubeV3::VideoSnippet.new(
          title:       title,
          description: description,
          category_id: category,
          tags:        tags
        ),
        status: Google::Apis::YoutubeV3::VideoStatus.new(
          privacy_status: privacy
        )
      )
    end

    def upload!(asset, video_resource)
      ext          = asset.file.attached? ? File.extname(asset.file.filename.to_s) : ""
      ext          = ".mp4" if ext.blank?
      content_type = asset.mime_type.presence || "video/mp4"
      tempfile     = Tempfile.new([ "yt_upload", ext ], binmode: true)

      Rails.logger.debug("[YouTube::VideoPublisher] Downloading MediaAsset##{asset.id} from #{asset.public_url}")
      URI.open(asset.public_url, "rb") { |src| IO.copy_stream(src, tempfile) }
      tempfile.rewind

      Rails.logger.debug("[YouTube::VideoPublisher] Uploading to YouTube (content_type=#{content_type})")

      result = @client.upload_video(tempfile.path, video_resource, content_type:)
      result.id || raise(YouTube::UploadError, "YouTube upload returned no video ID")
    ensure
      tempfile&.close
      tempfile&.unlink
    end
  end
end
