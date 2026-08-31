""# frozen_string_literal: true

module Admin
  module Instagram
    class AuthController < Admin::BaseController
      # ::Instagram — inside Admin::Instagram a bare Instagram:: would resolve
      # to this controller's own namespace.
      OAUTH_URL    = "https://www.facebook.com/#{::Instagram::ApiClient::GRAPH_VERSION}/dialog/oauth"
      OAUTH_SCOPES = %w[
        instagram_basic
        instagram_content_publish
        instagram_manage_comments
        instagram_manage_insights
        pages_show_list
        pages_read_engagement
        pages_manage_posts
        read_insights
        business_management
      ].freeze

      def connect
        @auth_url  = build_auth_url
        @connected = Current.user.instagram_connected?
      end

      def callback
        code       = params.require(:code).to_s
        service    = ::Instagram::AuthService.new(Current.user)
        long_lived = service.exchange_code_for_long_lived_token(code, redirect_uri: admin_instagram_callback_url)

        session[:ig_pending_token]      = long_lived[:token]
        session[:ig_pending_expires_in] = long_lived[:expires_in]

        @ig_accounts = service.list_ig_accounts(long_lived[:token])
        render :select_account
      rescue ActionController::ParameterMissing
        redirect_to admin_instagram_connect_path, alert: "No authorisation code was returned by Instagram."
      rescue ::Instagram::ApiError => e
        redirect_to admin_instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
      end

      def select_account
        ig_user_id = params.require(:ig_user_id)
        token      = session.delete(:ig_pending_token)
        expires_in = session.delete(:ig_pending_expires_in)

        raise ::Instagram::ApiError, "Session expired – please reconnect." if token.blank?

        finish_connection(token, expires_in, ig_user_id)
      rescue ActionController::ParameterMissing
        redirect_to admin_instagram_connect_path, alert: "No account was selected."
      rescue ::Instagram::ApiError => e
        redirect_to admin_instagram_connect_path, alert: "Instagram connection failed: #{e.message}"
      end

      def refresh_token
        ::Instagram::AuthService.new(Current.user).refresh_long_lived_token
        redirect_to admin_instagram_connect_path, notice: "Token refreshed — your connection is valid for another 60 days."
      rescue ::Instagram::TokenExpiredError
        redirect_to admin_instagram_connect_path, alert: "Your token has already expired. Please reconnect your account."
      rescue ::Instagram::ApiError => e
        redirect_to admin_instagram_connect_path, alert: "Could not refresh token: #{e.message}"
      end

      def disconnect
        Current.user.update!(
          instagram_access_token:     nil,
          instagram_token_expires_at: nil,
          instagram_user_id:          nil,
          instagram_page_id:          nil,
          instagram_username:         nil
        )
        redirect_to admin_instagram_connect_path, notice: "Instagram disconnected."
      end

      private

      def finish_connection(token, expires_in, ig_user_id)
        ::Instagram::AuthService.new(Current.user)
                                .connect_with_token(token, expires_in: expires_in, ig_user_id: ig_user_id)
        redirect_to admin_instagram_connect_path, notice: "Instagram account connected successfully."
      end

      def build_auth_url
        uri       = URI(OAUTH_URL)
        uri.query = URI.encode_www_form(
          client_id:     Rails.application.credentials.dig(:meta, :app_id),
          redirect_uri:  admin_instagram_callback_url,
          scope:         OAUTH_SCOPES.join(","),
          response_type: "code"
        )
        uri.to_s
      end
    end
  end
end
