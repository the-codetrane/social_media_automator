# frozen_string_literal: true

module Instagram
  class AuthController < ApplicationController
    OAUTH_URL    = "https://www.instagram.com/oauth/authorize"
    OAUTH_SCOPES = %w[
      instagram_business_basic
      instagram_manage_comments
      instagram_business_manage_messages
    ].freeze

    # GET /instagram/connect
    # Landing page with a "Connect Instagram" button.
    def connect
      @auth_url = build_auth_url
    end

    # GET /instagram/callback?code=…
    # Meta redirects here after the user grants permission.
    def callback
      code = params.require(:code)

      Instagram::AuthService.new(Current.user)
                            .exchange_code_for_token(code, redirect_uri: instagram_callback_url)

      redirect_to "/", notice: "Instagram account connected successfully."
    rescue ActionController::ParameterMissing
      redirect_to instagram_connect_path, alert: "No authorisation code was returned by Instagram."
    rescue Instagram::ApiError => e
      redirect_to instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
    end

    private

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
