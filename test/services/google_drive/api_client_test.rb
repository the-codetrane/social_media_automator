# frozen_string_literal: true

require "test_helper"

module GoogleDrive
  class ApiClientTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Setup
    # -------------------------------------------------------------------------

    def setup
      @drive  = connected_drives(:personal_drive)
      @client = GoogleDrive::ApiClient.new(@drive)
    end

    # Build a Faraday test connection that stubs a single GET path.
    def stub_connection(path, status:, body:)
      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get(path) { [ status, { "Content-Type" => "application/json" }, body.to_json ] }
      end
      Faraday.new { |f| f.response :json, content_type: /\bjson$/; f.adapter :test, stubs }
    end

    # -------------------------------------------------------------------------
    # #list_files
    # -------------------------------------------------------------------------

    test "list_files returns files array from Drive API" do
      files_body = {
        "files"         => [ { "id" => "abc", "name" => "photo.jpg", "mimeType" => "image/jpeg" } ],
        "nextPageToken" => nil
      }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, stub_connection("files", status: 200, body: files_body)) do
          result = @client.list_files(@drive.folder_id)
          assert_equal 1,     result["files"].length
          assert_equal "abc", result["files"].first["id"]
        end
      end
    end

    test "list_files includes pageToken param when provided" do
      files_body = { "files" => [], "nextPageToken" => nil }
      captured_params = nil

      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("files") do |env|
          captured_params = Rack::Utils.parse_query(env.url.query)
          [ 200, { "Content-Type" => "application/json" }, files_body.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, conn) do
          @client.list_files(@drive.folder_id, page_token: "token_xyz")
          assert_equal "token_xyz", captured_params["pageToken"]
        end
      end
    end

    test "list_files includes supportsAllDrives and includeItemsFromAllDrives params" do
      files_body = { "files" => [], "nextPageToken" => nil }
      captured_params = nil

      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("files") do |env|
          captured_params = Rack::Utils.parse_query(env.url.query)
          [ 200, { "Content-Type" => "application/json" }, files_body.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, conn) do
          @client.list_files(@drive.folder_id)
          assert_equal "true", captured_params["supportsAllDrives"]
          assert_equal "true", captured_params["includeItemsFromAllDrives"]
        end
      end
    end

    test "list_files sets Authorization header with bearer token" do
      files_body     = { "files" => [], "nextPageToken" => nil }
      captured_auth  = nil

      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.get("files") do |env|
          captured_auth = env.request_headers["Authorization"]
          [ 200, { "Content-Type" => "application/json" }, files_body.to_json ]
        end
      end
      conn = Faraday.new { |f| f.response :json; f.adapter :test, stubs }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, conn) do
          @client.list_files(@drive.folder_id)
          assert_equal "Bearer #{@drive.access_token}", captured_auth
        end
      end
    end

    # -------------------------------------------------------------------------
    # #refresh_access_token!
    # -------------------------------------------------------------------------

    test "refresh_access_token! raises TokenRefreshError when no refresh_token stored" do
      @drive.refresh_token = nil
      assert_raises(GoogleDrive::TokenRefreshError) { @client.refresh_access_token! }
    end

    test "refresh_access_token! updates access_token and token_expires_at on success" do
      new_token  = "ya29.new_access_token"
      expires_in = 3600

      token_body = { "access_token" => new_token, "token_type" => "Bearer", "expires_in" => expires_in }
      @client.stub(:exchange_refresh_token, token_body) do
        freeze_time do
          @client.refresh_access_token!
          updated = @drive.reload
          assert_equal new_token, updated.access_token
          assert_in_delta (Time.current + expires_in.seconds).to_i,
                          updated.token_expires_at.to_i,
                          2
        end
      end
    end

    test "refresh_access_token! raises TokenRefreshError when Google returns an error" do
      error_body = { "error" => "invalid_grant", "error_description" => "Token has been expired or revoked." }
      @client.stub(:exchange_refresh_token, error_body) do
        err = assert_raises(GoogleDrive::TokenRefreshError) { @client.refresh_access_token! }
        assert_match "Token has been expired or revoked.", err.message
      end
    end

    # -------------------------------------------------------------------------
    # Auto-refresh (ensure_token_fresh!)
    # -------------------------------------------------------------------------

    test "get triggers refresh_access_token! when token is expired" do
      @drive.token_expires_at = 1.hour.ago   # expired
      files_body = { "files" => [], "nextPageToken" => nil }
      refresh_called = false

      @client.stub(:refresh_access_token!, -> { refresh_called = true }) do
        @client.stub(:connection, stub_connection("files", status: 200, body: files_body)) do
          @client.list_files(@drive.folder_id)
        end
      end

      assert refresh_called, "Expected refresh_access_token! to be called for expired token"
    end

    test "get does not call refresh_access_token! when token is still valid" do
      @drive.token_expires_at = 1.hour.from_now  # still valid
      files_body = { "files" => [], "nextPageToken" => nil }
      refresh_called = false

      @client.stub(:refresh_access_token!, -> { refresh_called = true }) do
        @client.stub(:connection, stub_connection("files", status: 200, body: files_body)) do
          @client.list_files(@drive.folder_id)
        end
      end

      assert_not refresh_called, "Did not expect refresh_access_token! to be called for a valid token"
    end

    # -------------------------------------------------------------------------
    # handle_response
    # -------------------------------------------------------------------------

    test "list_files raises TokenExpiredError on HTTP 401" do
      error_body = { "error" => { "message" => "Invalid Credentials", "code" => 401 } }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, stub_connection("files", status: 401, body: error_body)) do
          assert_raises(GoogleDrive::TokenExpiredError) { @client.list_files(@drive.folder_id) }
        end
      end
    end

    test "list_files raises ApiError on HTTP 403" do
      error_body = { "error" => { "message" => "The user does not have sufficient permissions.", "code" => 403 } }

      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, stub_connection("files", status: 403, body: error_body)) do
          err = assert_raises(GoogleDrive::ApiError) { @client.list_files(@drive.folder_id) }
          assert_match "sufficient permissions", err.message
          assert_equal 403, err.code
        end
      end
    end

    test "list_files raises ApiError on HTTP 500" do
      @client.stub(:ensure_token_fresh!, nil) do
        @client.stub(:connection, stub_connection("files", status: 500, body: {})) do
          err = assert_raises(GoogleDrive::ApiError) { @client.list_files(@drive.folder_id) }
          assert_equal 500, err.code
        end
      end
    end
  end
end
