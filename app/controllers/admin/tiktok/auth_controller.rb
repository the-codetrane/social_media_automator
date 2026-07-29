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
        state = SecureRandom.hex(16)
        session[:tiktok_oauth_state] = state

        @mode            = ::TikTok.mode
        @modes           = ::TikTok::MODES
        @configured      = ::TikTok.configured?
        @mode_configured = @modes.index_with { |m| ::TikTok.configured?(for_mode: m) }

        @connected       = Current.user.tiktok_connected?
        @username        = Current.user.tiktok_username
        @expires_at      = Current.user.tiktok_token_expires_at
        @refresh_expired = Current.user.tiktok_refresh_expired?
        @environment     = Current.user.tiktok_environment
        @mode_mismatch   = mode_mismatch?

        # Only buildable when this mode's credentials exist; the view degrades to
        # a "not configured" notice rather than erroring on the whole page.
        @auth_url = (::TikTok::AuthService.new(Current.user).build_auth_url(
          redirect_uri: admin_tiktok_callback_url, state: state
        ) if @configured)
      end

      # Switch between the production and sandbox TikTok apps.
      def set_mode
        was_mismatched = mode_mismatch?
        previous_env   = Current.user.tiktok_environment

        ::TikTok.mode = params.require(:mode)

        notice = "TikTok mode set to #{::TikTok.mode}."
        if mode_mismatch? || was_mismatched
          notice += " The connected account was authorised by the #{previous_env} app — reconnect to publish."
        end

        redirect_to admin_tiktok_connect_path, notice: notice
      rescue ActionController::ParameterMissing, ArgumentError => e
        redirect_to admin_tiktok_connect_path, alert: "Could not change mode: #{e.message}"
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

      private

      # True when the stored token was minted by the app we are NOT currently
      # pointed at, so it cannot be used until the account is reconnected.
      def mode_mismatch?
        Current.user.tiktok_connected? &&
          Current.user.tiktok_environment.present? &&
          Current.user.tiktok_environment != ::TikTok.mode
      end
    end
  end
end
