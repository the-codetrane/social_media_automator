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
    # Graph API version. v26.0 is required for the Instagram Audio API
    # (GET /ig_audio, audio_configuration) and the IG Media collaborators edge.
    GRAPH_VERSION = "v26.0"
    BASE_URL      = "https://graph.facebook.com/#{GRAPH_VERSION}/"
    MAX_RETRIES   = 3

    # @param user [User] must have instagram_access_token present
    # @param access_token [String, nil] override the user's stored token (e.g. a Page access token)
    def initialize(user, access_token: nil)
      @user             = user
      @token_override   = access_token
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

    # POST to an absolute upload URL handed back by another endpoint.
    #
    # Meta's resumable upload host (rupload.facebook.com, used by the Page
    # Stories video flow) does not take the token as a form parameter the way
    # graph.facebook.com does: it wants an `Authorization: OAuth <token>` header,
    # and describes the source with headers rather than a body. This reuses the
    # Faraday stack — retries, JSON parsing, error raising — but skips
    # authenticated_params, which would put the token in the wrong place.
    #
    # @param url [String] absolute URL from an upload-session start response
    # @param headers [Hash] request headers, e.g. { "file_url" => "https://…" }
    # @return [Hash] parsed JSON body
    def post_upload(url, headers = {})
      response = connection.post(url) do |req|
        req.headers["Authorization"] = "OAuth #{access_token}"
        headers.each { |key, value| req.headers[key.to_s] = value.to_s }
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
      token = @token_override.presence || @user.instagram_access_token
      raise Instagram::TokenExpiredError, "User #{@user.id} has no Instagram access token" if token.blank?
      token
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
