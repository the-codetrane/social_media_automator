# frozen_string_literal: true

module TikTok
  # Low-level HTTP wrapper around the TikTok Open API v2.
  #
  # Differences from Instagram::ApiClient worth knowing:
  #   * Requests are JSON with a Bearer token, not form-encoded with an
  #     access_token parameter.
  #   * Every response carries an "error" object; success is error.code == "ok".
  #   * TikTok access tokens live for 24 hours, so the client refreshes them
  #     lazily via TikTok::AuthService before each request rather than relying
  #     on a manual admin action.
  #
  # Usage:
  #   client = TikTok::ApiClient.new(user)
  #   client.post("post/publish/creator_info/query/")
  #   client.post("post/publish/video/init/", post_info: {...}, source_info: {...})
  class ApiClient
    BASE_URL    = "https://open.tiktokapis.com/v2/"
    MAX_RETRIES = 3

    # Refresh the access token when it expires within this window.
    TOKEN_REFRESH_BUFFER = 5.minutes

    # Statuses the chunked upload endpoint returns for an accepted chunk.
    UPLOAD_SUCCESS_STATUSES = [ 200, 201, 206 ].freeze

    # @param user [User] must have tiktok_access_token present
    def initialize(user)
      @user = user
    end

    # Perform a GET request.
    #
    # @param path [String] path relative to BASE_URL
    # @param params [Hash] query parameters
    # @return [Hash] parsed JSON body
    def get(path, params = {})
      token = access_token

      response = connection.get(path) do |req|
        req.headers["Authorization"] = "Bearer #{token}"
        req.params.merge!(params.transform_keys(&:to_s))
      end

      handle_response(response)
    end

    # Perform a POST request with a JSON body.
    #
    # @param path [String] path relative to BASE_URL
    # @param body [Hash] body parameters, serialised to JSON
    # @return [Hash] parsed JSON body
    def post(path, body = {})
      token = access_token

      response = connection.post(path) do |req|
        req.headers["Authorization"] = "Bearer #{token}"
        req.headers["Content-Type"]  = "application/json; charset=UTF-8"
        req.body = body
      end

      handle_response(response)
    end

    # PUT one chunk of a FILE_UPLOAD transfer to the absolute upload_url
    # returned by /post/publish/video/init/.
    #
    # This bypasses the JSON connection entirely: the upload endpoint takes raw
    # binary, is not under BASE_URL, and is authorised by the signed URL itself
    # rather than the Bearer token.
    #
    # @param upload_url [String] absolute URL from the init response
    # @param bytes [String] binary chunk payload
    # @param content_type [String] MIME type of the whole file (e.g. "video/mp4")
    # @param first_byte [Integer] inclusive start offset of this chunk
    # @param last_byte [Integer] inclusive end offset of this chunk
    # @param total_bytes [Integer] total size of the file
    # @return [Integer] the HTTP status (206 while partial, 201 when complete)
    # @raise [TikTok::UploadError] when the chunk is rejected
    def upload_chunk(upload_url, bytes, content_type:, first_byte:, last_byte:, total_bytes:)
      response = upload_connection.put(upload_url) do |req|
        req.headers["Content-Type"]   = content_type
        req.headers["Content-Length"] = bytes.bytesize.to_s
        req.headers["Content-Range"]  = "bytes #{first_byte}-#{last_byte}/#{total_bytes}"
        req.body = bytes
      end

      unless UPLOAD_SUCCESS_STATUSES.include?(response.status)
        raise TikTok::UploadError,
              "Chunk upload failed with HTTP #{response.status} for bytes " \
              "#{first_byte}-#{last_byte}/#{total_bytes}: #{response.body}"
      end

      response.status
    end

    private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request  :json
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

    def upload_connection
      @upload_connection ||= Faraday.new do |f|
        f.request  :retry,
                   max: MAX_RETRIES,
                   interval: 1,
                   interval_randomness: 0.5,
                   backoff_factor: 2,
                   exceptions: [ Faraday::TimeoutError, Faraday::ServerError ]
        f.adapter  Faraday.default_adapter
      end
    end

    # Return a usable access token, refreshing it first when it is about to
    # expire.  TikTok access tokens are only valid for 24 hours.
    def access_token
      refresh_token_if_needed!

      token = @user.tiktok_access_token
      raise TikTok::TokenExpiredError, "User #{@user.id} has no TikTok access token" if token.blank?
      token
    end

    def refresh_token_if_needed!
      return if @user.tiktok_refresh_token.blank?
      return unless @user.tiktok_token_expiring?(buffer: TOKEN_REFRESH_BUFFER)

      Rails.logger.info("[TikTok::ApiClient] Refreshing access token for User##{@user.id}")
      TikTok::AuthService.new(@user).refresh_access_token!
    end

    # TikTok always returns an "error" object; error.code == "ok" means success.
    def handle_response(response)
      body = response.body
      body = {} unless body.is_a?(Hash)

      error = body["error"]
      code  = error.is_a?(Hash) ? error["code"] : nil

      if code.present? && code != "ok"
        raise TikTok.error_class_for(code).new(
          error["message"].presence || "TikTok API error '#{code}'",
          code:   code,
          log_id: error["log_id"]
        )
      end

      # A non-2xx response without a recognisable error object still needs to blow up.
      if response.status >= 400
        raise TikTok::ApiError, "TikTok API returned HTTP #{response.status}: #{body.inspect}"
      end

      body
    end
  end
end
