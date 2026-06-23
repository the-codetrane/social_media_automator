# frozen_string_literal: true

require "signet/oauth_2/client"

module YouTube
  # Handles the Google OAuth 2.0 flow for YouTube channel authorisation.
  #
  # The resulting refresh token is persisted in AppSetting so it survives
  # deploys and can be rotated from the admin UI without touching credentials.
  class AuthService
    AUTH_URI  = "https://accounts.google.com/o/oauth2/auth"
    TOKEN_URI = "https://oauth2.googleapis.com/token"
    SCOPES    = %w[
      https://www.googleapis.com/auth/youtube.upload
      https://www.googleapis.com/auth/youtube.readonly
    ].freeze

    # Build the Google consent-screen URL for the given callback.
    def build_auth_url(redirect_uri:)
      oauth_client(redirect_uri: redirect_uri).authorization_uri(
        access_type: "offline",
        prompt:      "consent"
      ).to_s
    end

    # Exchange the authorisation code for tokens and persist the refresh token.
    def exchange_code(code, redirect_uri:)
      client = oauth_client(redirect_uri: redirect_uri)
      client.code = code
      client.fetch_access_token!

      AppSetting.set("youtube_refresh_token", client.refresh_token)

      channel_title = fetch_channel_title(client.access_token)
      AppSetting.set("youtube_channel_title", channel_title) if channel_title
    end

    def connected?
      AppSetting.get("youtube_refresh_token").present?
    end

    def channel_title
      AppSetting.get("youtube_channel_title")
    end

    def disconnect
      AppSetting.find_by(key: "youtube_refresh_token")&.destroy
      AppSetting.find_by(key: "youtube_channel_title")&.destroy
    end

    private

    def oauth_client(redirect_uri:)
      Signet::OAuth2::Client.new(
        authorization_uri:    AUTH_URI,
        token_credential_uri: TOKEN_URI,
        client_id:     Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        redirect_uri:  redirect_uri,
        scope:         SCOPES.join(" ")
      )
    end

    def fetch_channel_title(access_token)
      uri = URI("https://www.googleapis.com/youtube/v3/channels")
      uri.query = URI.encode_www_form(part: "snippet", mine: "true")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response = http.get(uri.request_uri, "Authorization" => "Bearer #{access_token}")

      JSON.parse(response.body).dig("items", 0, "snippet", "title")
    rescue => e
      Rails.logger.warn("[YouTube::AuthService] Could not fetch channel title: #{e.message}")
      nil
    end
  end
end
