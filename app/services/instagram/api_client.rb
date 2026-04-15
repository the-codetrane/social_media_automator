# frozen_string_literal: true

module Instagram
  # Low-level HTTP wrapper around the Meta Graph API.
  #
  # Every request is authenticated with the User's stored access token.
  # Transient server errors (5xx) are retried up to 3 times with
  # exponential back-off courtesy of faraday-retry.
  #
  # Usage:
  #   client = Instagram::ApiClient.new(user)
  #   client.get("me/accounts")
  #   client.post("#{ig_id}/media", image_url: "...", caption: "...")
  class ApiClient
    BASE_URL     = "https://graph.facebook.com/v25.0/"
    MAX_RETRIES  = 3

    # @param user [User] must have instagram_access_token present
    def initialize(user)
      @user = user
    end

    # Perform a GET request.
    # @param path [String] path relative to BASE_URL
    # @param params [Hash] additional query parameters
    # @return [Hash] parsed JSON body
    def get(path, params = {})
      response = connection.get(path) do |req|
        req.params.merge!(authenticated_params(params))
      end
      handle_response(response)
    end

    # Perform a POST request with form-encoded body.
    # @param path [String] path relative to BASE_URL
    # @param body [Hash] body parameters
    # @return [Hash] parsed JSON body
    def post(path, body = {})
      response = connection.post(path) do |req|
        req.body = authenticated_params(body)
      end
      handle_response(response)
    end

    # Check how many API-published posts remain in the current 24 h window.
    # @return [Hash] { quota_usage: Integer, config: Hash }
    def publishing_limit(ig_user_id)
      get("#{ig_user_id}/content_publishing_limit", fields: "config,quota_usage")
    end

    private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request  :url_encoded
        f.request  :retry,
                   max: MAX_RETRIES,
                   interval: 1,
                   interval_randomness: 0.5,
                   backoff_factor: 2,
                   exceptions: [ Faraday::TimeoutError, Faraday::ServerError ]
        f.response :json, content_type: /\bjson$/
        f.adapter  Faraday.default_adapter
      end
    end

    def authenticated_params(params)
      { access_token: access_token }.merge(params.transform_keys(&:to_s))
    end

    def access_token
      raise Instagram::TokenExpiredError, "User #{@user.id} has no Instagram access token" if @user.instagram_access_token.blank?
      @user.instagram_access_token
    end

    def handle_response(response)
      body = response.body

      # Faraday :json middleware already parses the body into a Hash.
      if body.is_a?(Hash) && body["error"]
        err = body["error"]
        klass = rate_limit_error?(err) ? Instagram::RateLimitError : Instagram::ApiError
        raise klass.new(
          err["message"],
          code:       err["code"],
          type:       err["type"],
          fbtrace_id: err["fbtrace_id"]
        )
      end

      body
    end

    def rate_limit_error?(err)
      # Meta returns error code 32 for Page-level rate limits and 4 for
      # application-level rate limits.  The content publishing quota
      # exhaustion also surfaces as code 9007.
      [ 4, 32, 9007 ].include?(err["code"].to_i)
    end
  end
end
