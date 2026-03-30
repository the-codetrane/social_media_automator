# frozen_string_literal: true

module GoogleDrive
  # Low-level HTTP wrapper around the Google Drive API v3.
  #
  # Every request is authenticated with the access token stored on the
  # ConnectedDrive record.  If the token is expired before the request is
  # made, it is refreshed automatically using the stored refresh token.
  # Transient server errors (5xx) are retried up to 3 times with exponential
  # back-off courtesy of faraday-retry.
  #
  # Google OAuth 2.0 credentials (client_id / client_secret) are read from
  # Rails credentials under the :google key:
  #
  #   google:
  #     client_id: "..."
  #     client_secret: "..."
  #
  # Usage:
  #   client = GoogleDrive::ApiClient.new(connected_drive)
  #   page   = client.list_files(connected_drive.folder_id)
  #   while (token = page["nextPageToken"])
  #     page = client.list_files(connected_drive.folder_id, page_token: token)
  #   end
  class ApiClient
    BASE_URL    = "https://www.googleapis.com/drive/v3/"
    TOKEN_URL   = "https://oauth2.googleapis.com/token"
    MAX_RETRIES = 3

    # Fields requested for every file returned by files.list.
    FILE_FIELDS = "files(id,name,mimeType,size,webViewLink,webContentLink," \
                  "thumbnailLink,imageMediaMetadata,videoMediaMetadata,createdTime)," \
                  "nextPageToken"

    # @param connected_drive [ConnectedDrive]
    def initialize(connected_drive)
      @connected_drive = connected_drive
    end

    # List files inside a Drive folder, requesting only the metadata fields
    # we care about.  Supports shared drives via supportsAllDrives.
    #
    # @param folder_id [String]
    # @param page_token [String, nil] pagination cursor from a previous call
    # @return [Hash] { "files" => Array<Hash>, "nextPageToken" => String|nil }
    def list_files(folder_id, page_token: nil)
      params = {
        q:                         "'#{folder_id}' in parents and trashed=false",
        fields:                    FILE_FIELDS,
        supportsAllDrives:         true,
        includeItemsFromAllDrives: true,
        pageSize:                  100
      }
      params[:pageToken] = page_token if page_token

      get("files", params)
    end

    # Exchange the stored refresh token for a new access token and persist it
    # on the ConnectedDrive record.
    #
    # @raise [GoogleDrive::TokenRefreshError] if no refresh token is stored or
    #   Google returns an error.
    # @return [void]
    def refresh_access_token!
      if @connected_drive.refresh_token.blank?
        raise GoogleDrive::TokenRefreshError,
              "No refresh token stored for ConnectedDrive##{@connected_drive.id}"
      end

      body = exchange_refresh_token

      if body["error"]
        raise GoogleDrive::TokenRefreshError,
              body["error_description"] || body["error"]
      end

      @connected_drive.update!(
        access_token:     body["access_token"],
        token_expires_at: Time.current + body["expires_in"].to_i.seconds
      )
    end

    private

    # -------------------------------------------------------------------------
    # HTTP helpers
    # -------------------------------------------------------------------------

    def get(path, params = {})
      ensure_token_fresh!

      response = connection.get(path) do |req|
        req.params.merge!(params.transform_keys(&:to_s))
        req.headers["Authorization"] = "Bearer #{@connected_drive.access_token}"
      end

      handle_response(response)
    end

    def ensure_token_fresh!
      refresh_access_token! if @connected_drive.token_expired?
    end

    # Perform the HTTP token-exchange POST.  Extracted into its own method so
    # it can be stubbed in tests without reaching the network.
    #
    # @return [Hash] parsed JSON response body
    def exchange_refresh_token
      response = Faraday.post(TOKEN_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          grant_type:    "refresh_token",
          refresh_token: @connected_drive.refresh_token,
          client_id:     Rails.application.credentials.dig(:google, :client_id),
          client_secret: Rails.application.credentials.dig(:google, :client_secret)
        )
      end
      JSON.parse(response.body)
    end

    def handle_response(response)
      body = response.body
      body = {} unless body.is_a?(Hash)

      case response.status
      when 200..299
        body
      when 401
        raise GoogleDrive::TokenExpiredError,
              body.dig("error", "message") || "Access token expired or revoked"
      else
        raise GoogleDrive::ApiError.new(
          body.dig("error", "message") || "Google Drive API error (HTTP #{response.status})",
          code: response.status
        )
      end
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request  :retry,
                   max:                 MAX_RETRIES,
                   interval:            1,
                   interval_randomness: 0.5,
                   backoff_factor:      2,
                   exceptions:          [ Faraday::TimeoutError, Faraday::ServerError ]
        f.response :json, content_type: /\bjson$/
        f.adapter  Faraday.default_adapter
      end
    end
  end
end
