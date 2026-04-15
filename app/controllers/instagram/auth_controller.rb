# frozen_string_literal: true

module Instagram
  class AuthController < ApplicationController
    OAUTH_URL    = "https://www.facebook.com/v25.0/dialog/oauth"
    OAUTH_SCOPES = %w[
      instagram_basic
      instagram_content_publish
      instagram_manage_comments
      pages_show_list
      pages_read_engagement
      business_management
    ].freeze

    # GET /instagram/connect
    # Landing page with a "Connect Instagram" button.
    def connect
      @auth_url = build_auth_url
    end

    # GET /instagram/callback?code=…
    # Instagram redirects here after the user grants permission.
    def callback
      code    = params.require(:code).to_s
      service = Instagram::AuthService.new(Current.user)
      service.exchange_code_for_token(code, redirect_uri: instagram_callback_url)
      redirect_to "/", notice: "Instagram account connected successfully."
    rescue ActionController::ParameterMissing
      redirect_to instagram_connect_path, alert: "No authorisation code was returned by Instagram."
    rescue Instagram::ApiError => e
      redirect_to instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
    end

    # POST /instagram/select_account
    # Finalises the connection for the chosen Instagram Business Account.
    def select_account
      ig_user_id = params.require(:ig_user_id)
      token      = session.delete(:ig_pending_token)
      expires_in = session.delete(:ig_pending_expires_in)

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
