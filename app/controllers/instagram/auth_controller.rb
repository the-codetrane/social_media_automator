# frozen_string_literal: true

module Instagram
  class AuthController < ApplicationController
    # Facebook Login is required to access Instagram Business/Creator accounts
    # via the Graph API (/me/accounts). Using instagram.com/oauth/authorize
    # (Instagram Basic Display API) with a Facebook-Login app causes the
    # "Invalid platform app" error.
    OAUTH_URL    = "https://www.facebook.com/v20.0/dialog/oauth"
    OAUTH_SCOPES = %w[
      business_management
      instagram_basic
      pages_read_engagement
      pages_show_list
    ].freeze

    # GET /instagram/connect
    # Landing page with a "Connect Instagram" button.
    def connect
      @auth_url = build_auth_url
    end

    # GET /instagram/callback?code=…
    # Meta redirects here after the user grants permission.
    def callback
      code    = params.require(:code).to_s
      service = Instagram::AuthService.new(Current.user)

      # Exchange code → long-lived token via the service's public helpers.
      long_lived = service.exchange_code_for_long_lived_token(code, redirect_uri: instagram_callback_url)

      session[:ig_pending_token]      = long_lived[:token]
      session[:ig_pending_expires_in] = long_lived[:expires_in]

      @ig_accounts = service.list_ig_accounts(long_lived[:token])

      if @ig_accounts.size == 1
        finish_connection(long_lived[:token], long_lived[:expires_in], @ig_accounts.first[:ig_user_id])
      else
        render :select_account
      end
    rescue ActionController::ParameterMissing
      redirect_to instagram_connect_path, alert: "No authorisation code was returned by Facebook."
    rescue Instagram::ApiError => e
      redirect_to instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
    end

    # POST /instagram/select_account
    # Finalises the connection for the chosen Instagram Business Account.
    def select_account
      ig_user_id  = params.require(:ig_user_id)
      token       = session.delete(:ig_pending_token)
      expires_in  = session.delete(:ig_pending_expires_in)

      raise Instagram::ApiError, "Session expired – please reconnect." if token.blank?

      finish_connection(token, expires_in, ig_user_id)
    rescue ActionController::ParameterMissing
      redirect_to instagram_connect_path, alert: "No account was selected."
    rescue Instagram::ApiError => e
      redirect_to instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
    end

    private

    def finish_connection(token, expires_in, ig_user_id)
      Instagram::AuthService.new(Current.user)
                            .connect_with_token(token, expires_in: expires_in, ig_user_id: ig_user_id)
      redirect_to "/", notice: "Instagram account connected successfully."
    end

    def build_auth_url
      uri       = URI(OAUTH_URL)
      uri.query = URI.encode_www_form(
        client_id:     Rails.application.credentials.dig(:meta, :app_id),
        redirect_uri:  instagram_callback_url,
        scope:         OAUTH_SCOPES.join(","),
        response_type: "code"
      )
      uri.to_s
    end
  end
end
