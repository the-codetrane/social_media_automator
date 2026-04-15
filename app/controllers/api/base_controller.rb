# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_key!

    private

    def authenticate_api_key!
      api_key = request.headers["X-API-AUTH"]

      if api_key.blank?
        render json: { error: "Missing API key" }, status: :unauthorized
        return
      end

      unless ActiveSupport::SecurityUtils.secure_compare(api_key, expected_api_key)
        render json: { error: "Invalid API key" }, status: :unauthorized
      end
    end

    def expected_api_key
      Rails.application.credentials.dig(:api, :key) || ENV["API_KEY"]
    end
  end
end
