# frozen_string_literal: true

module Admin
  module TikTok
    # Drives the TikTok Login Kit OAuth flow for the signed-in admin.
    #
    # Unlike the YouTube connection (a single app-wide refresh token in
    # AppSetting), TikTok credentials are per-creator and are stored on the
    # User record, the same way Instagram's are.
    class AuthController < Admin::BaseController
      def connect
        service    = ::TikTok::AuthService.new(Current.user)
        state      = SecureRandom.hex(16)
        session[:tiktok_oauth_state] = state

        @auth_url  = service.build_auth_url(redirect_uri: admin_tiktok_callback_url, state: state)
        @connected = Current.user.tiktok_connected?
        @username  = Current.user.tiktok_username
        @expires_at = Current.user.tiktok_token_expires_at
        @refresh_expired = Current.user.tiktok_refresh_expired?
      end

      def callback
        code           = params.require(:code).to_s
        expected_state = session.delete(:tiktok_oauth_state)

        if expected_state.present? && params[:state].to_s != expected_state
          return redirect_to admin_tiktok_connect_path, alert: "TikTok connection failed: state mismatch."
        end

        ::TikTok::AuthService.new(Current.user).exchange_code(code, redirect_uri: admin_tiktok_callback_url)
        redirect_to admin_tiktok_connect_path, notice: "TikTok connected successfully."
      rescue ActionController::ParameterMissing
        redirect_to admin_tiktok_connect_path, alert: "No authorisation code was returned by TikTok."
      rescue ::TikTok::Error => e
        redirect_to admin_tiktok_connect_path, alert: "TikTok connection failed: #{e.message}"
      end

      def refresh_token
        ::TikTok::AuthService.new(Current.user).refresh_access_token!
        redirect_to admin_tiktok_connect_path, notice: "TikTok access token refreshed."
      rescue ::TikTok::Error => e
        redirect_to admin_tiktok_connect_path, alert: "Could not refresh token: #{e.message}"
      end

      def disconnect
        ::TikTok::AuthService.new(Current.user).disconnect
        redirect_to admin_tiktok_connect_path, notice: "TikTok disconnected."
      end
    end
  end
end
