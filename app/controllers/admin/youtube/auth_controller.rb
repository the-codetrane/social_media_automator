# frozen_string_literal: true

module Admin
  module YouTube
    class AuthController < Admin::BaseController
      def connect
        @service       = ::YouTube::AuthService.new
        @auth_url      = @service.build_auth_url(redirect_uri: admin_youtube_callback_url)
        @connected     = @service.connected?
        @channel_title = @service.channel_title
      end

      def callback
        service = ::YouTube::AuthService.new
        service.exchange_code(params.require(:code), redirect_uri: admin_youtube_callback_url)
        redirect_to admin_youtube_connect_path, notice: "YouTube connected successfully."
      rescue ActionController::ParameterMissing
        redirect_to admin_youtube_connect_path, alert: "No authorisation code returned by Google."
      rescue Signet::AuthorizationError, ::YouTube::TokenExpiredError => e
        redirect_to admin_youtube_connect_path, alert: "Authorisation failed: #{e.message}"
      end

      def disconnect
        ::YouTube::AuthService.new.disconnect
        redirect_to admin_youtube_connect_path, notice: "YouTube disconnected."
      end
    end
  end
end
