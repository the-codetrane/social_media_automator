# frozen_string_literal: true

require "google/apis/youtube_v3"
require "googleauth"

module YouTube
  # Low-level wrapper around the Google::Apis::YoutubeV3::YouTubeService.
  #
  # Reads app-level OAuth 2.0 credentials from Rails encrypted credentials:
  #   google:
  #     client_id:     "…"
  #     client_secret: "…"
  #     refresh_token: "…"
  #
  # The google-apis-youtube_v3 gem handles token refresh automatically via
  # Google::Auth::UserRefreshCredentials.
  class ApiClient
    UPLOAD_SCOPE = "https://www.googleapis.com/auth/youtube.upload"

    def initialize
      @service = Google::Apis::YoutubeV3::YouTubeService.new
      @service.client_options.application_name = "SocialMediaAutomator"
      @service.authorization = build_credentials
    end

    # Upload a video file to YouTube.
    #
    # @param file_path     [String]  local path to the video file
    # @param video         [Google::Apis::YoutubeV3::Video] metadata resource
    # @param content_type  [String]  MIME type (e.g. "video/mp4")
    # @return [Google::Apis::YoutubeV3::Video] the created video resource (with .id set)
    def upload_video(file_path, video, content_type: "video/mp4")
      @service.insert_video(
        "snippet,status",
        video,
        upload_source: file_path,
        content_type:  content_type
      )
    rescue Signet::AuthorizationError, Google::Apis::AuthorizationError => e
      body = e.respond_to?(:body) ? e.body : nil
      Rails.logger.error("[YouTube::ApiClient] AuthorizationError body: #{body}")
      raise YouTube::TokenExpiredError, "YouTube authorization failed: #{e.message}"
    rescue Google::Apis::RateLimitError => e
      raise YouTube::RateLimitError, "YouTube quota exceeded: #{e.message}"
    rescue Google::Apis::Error => e
      raise YouTube::ApiError, "YouTube API error (#{e.status_code}): #{e.message}"
    end

    private

    def build_credentials
      Google::Auth::UserRefreshCredentials.new(
        client_id:     Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        refresh_token: AppSetting.get("youtube_refresh_token"),
        scope:         UPLOAD_SCOPE
      )
    end
  end
end
