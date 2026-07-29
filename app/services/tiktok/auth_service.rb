# frozen_string_literal: true

module TikTok
  # Handles the TikTok Login Kit OAuth 2.0 flow and token lifecycle.
  #
  # TikTok issues a 24-hour access token alongside a 365-day refresh token, so
  # unlike the Instagram integration (60-day token, manual refresh button) the
  # refresh has to happen automatically.  TikTok::ApiClient calls
  # #refresh_access_token! before any request whose token is about to expire.
  #
  # Usage — exchange the code from the OAuth callback:
  #   service = TikTok::AuthService.new(user)
  #   service.exchange_code(code, redirect_uri: "...")
  #
  # Usage — refresh proactively:
  #   TikTok::AuthService.new(user).refresh_access_token!
  class AuthService
    AUTH_URL   = "https://www.tiktok.com/v2/auth/authorize/"
    TOKEN_URL  = "https://open.tiktokapis.com/v2/oauth/token/"
    REVOKE_URL = "https://open.tiktokapis.com/v2/oauth/revoke/"

    # video.publish is required by every Content Posting API endpoint,
    # including creator_info/query.
    SCOPES = %w[user.info.basic video.publish].freeze

    # @param user [User]
    def initialize(user)
      @user          = user
      @client_key    = Rails.application.credentials.dig(:tiktok, :client_key)
      @client_secret = Rails.application.credentials.dig(:tiktok, :client_secret)
    end

    # Build the TikTok consent-screen URL.
    #
    # @param redirect_uri [String] must exactly match a redirect URI registered
    #   in the TikTok developer portal
    # @param state [String] CSRF token echoed back on the callback
    # @return [String]
    def build_auth_url(redirect_uri:, state: SecureRandom.hex(16))
      uri       = URI(AUTH_URL)
      uri.query = URI.encode_www_form(
        client_key:    @client_key,
        scope:         SCOPES.join(","),
        response_type: "code",
        redirect_uri:  redirect_uri,
        state:         state
      )
      uri.to_s
    end

    # Exchange the authorisation code for tokens and persist them on the User.
    #
    # @param code [String] the `code` query param from the OAuth callback
    # @param redirect_uri [String] must match the one used for build_auth_url
    # @return [User] the updated user
    def exchange_code(code, redirect_uri:)
      result = token_request(
        client_key:    @client_key,
        client_secret: @client_secret,
        code:          CGI.unescape(code.to_s),
        grant_type:    "authorization_code",
        redirect_uri:  redirect_uri
      )

      persist_tokens!(result)
      store_creator_username
      @user
    end

    # Exchange the stored refresh token for a fresh access token.
    #
    # TikTok may rotate the refresh token, so any new value in the response is
    # persisted too.
    #
    # @return [User] the updated user
    # @raise [TikTok::TokenExpiredError] when there is nothing to refresh
    def refresh_access_token!
      if @user.tiktok_refresh_token.blank?
        raise TikTok::TokenExpiredError, "User #{@user.id} has no TikTok refresh token"
      end

      result = token_request(
        client_key:    @client_key,
        client_secret: @client_secret,
        grant_type:    "refresh_token",
        refresh_token: @user.tiktok_refresh_token
      )

      persist_tokens!(result)
      @user
    end

    # Revoke the app's access with TikTok, then clear the stored credentials.
    # Revocation is best-effort — a failure there must not leave stale tokens
    # on the User record.
    def disconnect
      revoke
      clear_credentials!
    end

    private

    def revoke
      return if @user.tiktok_access_token.blank?

      token_connection.post(REVOKE_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          client_key:    @client_key,
          client_secret: @client_secret,
          token:         @user.tiktok_access_token
        )
      end
    rescue Faraday::Error => e
      Rails.logger.warn("[TikTok::AuthService] Could not revoke token for User##{@user.id}: #{e.message}")
    end

    def clear_credentials!
      @user.update!(
        tiktok_open_id:            nil,
        tiktok_access_token:       nil,
        tiktok_token_expires_at:   nil,
        tiktok_refresh_token:      nil,
        tiktok_refresh_expires_at: nil,
        tiktok_username:           nil,
        tiktok_scope:              nil
      )
    end

    def persist_tokens!(result)
      @user.update!(
        tiktok_open_id:            result["open_id"].presence || @user.tiktok_open_id,
        tiktok_access_token:       result["access_token"],
        tiktok_token_expires_at:   Time.current + result["expires_in"].to_i.seconds,
        tiktok_refresh_token:      result["refresh_token"].presence || @user.tiktok_refresh_token,
        tiktok_refresh_expires_at: refresh_expires_at(result),
        tiktok_scope:              result["scope"].presence || @user.tiktok_scope
      )
    end

    def refresh_expires_at(result)
      return @user.tiktok_refresh_expires_at if result["refresh_expires_in"].blank?
      Time.current + result["refresh_expires_in"].to_i.seconds
    end

    # The creator's @username comes back from creator_info/query, which the
    # video.publish scope already covers — no extra scope needed just to label
    # the connection in the admin UI.
    def store_creator_username
      info = TikTok::CreatorInfoService.new(@user).query
      @user.update!(tiktok_username: info["creator_username"]) if info["creator_username"].present?
    rescue TikTok::Error, Faraday::Error => e
      Rails.logger.warn("[TikTok::AuthService] Could not fetch creator username: #{e.message}")
    end

    # The OAuth endpoints are form-encoded and report failures as a flat
    # {error:, error_description:} pair rather than the nested error object
    # used by the rest of the v2 API.
    def token_request(params)
      response = token_connection.post(TOKEN_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
      end

      body = response.body
      body = JSON.parse(body) rescue {} if body.is_a?(String)
      body = {} unless body.is_a?(Hash)

      error = body["error"]
      if error.present? && error != "ok"
        raise TikTok.error_class_for(error).new(
          body["error_description"].presence || "TikTok OAuth error '#{error}'",
          code:   error,
          log_id: body["log_id"]
        )
      end

      if body["access_token"].blank?
        raise TikTok::TokenExpiredError, "TikTok returned no access token: #{body.inspect}"
      end

      body
    end

    def token_connection
      @token_connection ||= Faraday.new do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter  Faraday.default_adapter
      end
    end
  end
end
