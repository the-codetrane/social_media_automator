# frozen_string_literal: true

module Instagram
  # Handles OAuth 2.0 token exchange and Instagram Business Account discovery.
  #
  # Usage — exchange a short-lived code from the OAuth callback:
  #   service = Instagram::AuthService.new(user)
  #   service.exchange_code_for_token(code)        # stores long-lived token + ig_user_id
  #
  # Usage — proactively refresh before the token expires:
  #   service = Instagram::AuthService.new(user)
  #   service.refresh_long_lived_token             # updates token + expiry in DB
  class AuthService
    GRAPH_BASE   = "https://graph.facebook.com/v21.0/"
    TOKEN_URL    = "#{GRAPH_BASE}oauth/access_token"

    # @param user [User]
    def initialize(user)
      @user   = user
      @app_id     = Rails.application.credentials.dig(:meta, :app_id)
      @app_secret = Rails.application.credentials.dig(:meta, :app_secret)
    end

    # Exchange a short-lived authorisation code (from the OAuth redirect) for
    # a long-lived token and persist it + the IG account ID on the User record.
    #
    # @param code [String] the `code` query param from the OAuth callback
    # @param redirect_uri [String] must match the URI registered in the Meta app
    # @return [User] the updated user
    def exchange_code_for_token(code, redirect_uri:)
      # Step 1 – get a short-lived user access token
      short_lived = fetch_short_lived_token(code, redirect_uri)

      # Step 2 – exchange for a long-lived token (60-day expiry)
      long_lived  = fetch_long_lived_token(short_lived)

      # Step 3 – discover the connected Instagram Business Account
      ig_user_id, page_id = fetch_ig_user_id(long_lived[:token])

      # Step 4 – persist everything
      @user.update!(
        instagram_access_token:    long_lived[:token],
        instagram_token_expires_at: Time.current + long_lived[:expires_in].to_i.seconds,
        instagram_user_id:         ig_user_id,
        instagram_page_id:         page_id
      )

      @user
    end

    # Refresh the stored long-lived token (Meta allows refreshing any time it
    # has been active for more than 24 hours and hasn't yet expired).
    #
    # @return [User] the updated user
    def refresh_long_lived_token
      raise Instagram::TokenExpiredError, "No token to refresh for user #{@user.id}" if @user.instagram_access_token.blank?

      result = graph_get(TOKEN_URL,
        grant_type:         "fb_exchange_token",
        client_id:          @app_id,
        client_secret:      @app_secret,
        fb_exchange_token:  @user.instagram_access_token
      )

      @user.update!(
        instagram_access_token:    result["access_token"],
        instagram_token_expires_at: Time.current + result["expires_in"].to_i.seconds
      )

      @user
    end

    # Return true if the user's token is expired or will expire within
    # +buffer+ seconds (default 7 days).
    def token_expiring?(buffer: 7.days)
      return true if @user.instagram_token_expires_at.blank?
      @user.instagram_token_expires_at <= Time.current + buffer
    end

    private

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def fetch_short_lived_token(code, redirect_uri)
      response = graph_get(TOKEN_URL,
        client_id:     @app_id,
        client_secret: @app_secret,
        redirect_uri:  redirect_uri,
        code:          code
      )
      response["access_token"]
    end

    def fetch_long_lived_token(short_lived_token)
      response = graph_get(TOKEN_URL,
        grant_type:        "fb_exchange_token",
        client_id:         @app_id,
        client_secret:     @app_secret,
        fb_exchange_token: short_lived_token
      )
      { token: response["access_token"], expires_in: response["expires_in"] }
    end

    # Walk /me/accounts to find a Facebook Page that has a connected
    # Instagram Business Account.
    #
    # @return [Array<String, String>] [ig_user_id, page_id]
    def fetch_ig_user_id(access_token)
      accounts = graph_get("#{GRAPH_BASE}me/accounts",
        access_token: access_token,
        fields:       "id,name,instagram_business_account"
      )

      pages = accounts["data"] || []
      page  = pages.find { |p| p["instagram_business_account"].present? }

      raise Instagram::ApiError, "No Instagram Business Account found for this Facebook user." unless page

      [ page["instagram_business_account"]["id"], page["id"] ]
    end

    def graph_get(url, params)
      uri      = URI(url)
      uri.query = URI.encode_www_form(params)

      http     = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      response = http.get(uri.request_uri)

      body = JSON.parse(response.body)
      raise Instagram::ApiError.new(body.dig("error", "message"), code: body.dig("error", "code")) if body["error"]

      body
    end
  end
end
