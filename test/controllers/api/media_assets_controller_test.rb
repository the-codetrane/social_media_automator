# frozen_string_literal: true

require "test_helper"

module Api
  class MediaAssetsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @valid_api_key = "test_api_key_12345"
    end

    # ===========================================
    # Index — Authentication
    # ===========================================

    test "index returns unauthorized without API key" do
      get api_media_assets_path
      assert_response :unauthorized
    end

    test "index returns unauthorized with invalid API key" do
      stub_api_key do
        get api_media_assets_path, headers: { "X-API-AUTH" => "wrong" }
        assert_response :unauthorized
      end
    end

    # ===========================================
    # Index — Basic listing
    # ===========================================

    test "index returns all assets" do
      stub_api_key do
        get api_media_assets_path, headers: api_headers
        assert_response :ok
        assert_instance_of Array, response.parsed_body
        assert response.parsed_body.size >= MediaAsset.count
      end
    end

    test "index response includes expected fields" do
      stub_api_key do
        get api_media_assets_path, headers: api_headers
        asset = response.parsed_body.first
        %w[id external_id external_name media_type status public_url
           width height file_size duration_seconds mime_type
           first_seen_at created_at updated_at].each do |key|
          assert_includes asset.keys, key
        end
      end
    end

    # ===========================================
    # Index — Filtering
    # ===========================================

    test "index filters by media_type" do
      stub_api_key do
        get api_media_assets_path, params: { media_type: "video" }, headers: api_headers
        assert_response :ok
        assert response.parsed_body.all? { |a| a["media_type"] == "video" }
        assert response.parsed_body.size >= 1
      end
    end

    test "index filters by status" do
      stub_api_key do
        get api_media_assets_path, params: { status: "processed" }, headers: api_headers
        assert_response :ok
        assert response.parsed_body.all? { |a| a["status"] == "processed" }
      end
    end

    test "index filters by mime_type" do
      stub_api_key do
        get api_media_assets_path, params: { mime_type: "video/mp4" }, headers: api_headers
        assert_response :ok
        assert response.parsed_body.all? { |a| a["media_type"] == "video" }
        assert response.parsed_body.size >= 1
      end
    end

    test "index filters by first_seen_at_after" do
      stub_api_key do
        cutoff = 3.days.ago.iso8601
        get api_media_assets_path, params: { first_seen_at_after: cutoff }, headers: api_headers
        assert_response :ok
        assert response.parsed_body.all? { |a| Time.parse(a["first_seen_at"]) >= 3.days.ago }
      end
    end

    test "index filters by first_seen_at_before" do
      stub_api_key do
        cutoff = 1.hour.ago.iso8601
        get api_media_assets_path, params: { first_seen_at_before: cutoff }, headers: api_headers
        assert_response :ok
        response.parsed_body.each do |a|
          assert Time.parse(a["first_seen_at"]) <= 1.hour.ago
        end
      end
    end

    # ===========================================
    # Index — Search
    # ===========================================

    test "index search by external_name" do
      stub_api_key do
        get api_media_assets_path, params: { q: "sunset" }, headers: api_headers
        assert_response :ok
        names = response.parsed_body.map { |a| a["external_name"] }
        assert_includes names, "sunset.jpg"
        assert_not_includes names, "reel.mp4"
      end
    end

    test "index search is case insensitive" do
      stub_api_key do
        get api_media_assets_path, params: { q: "SUNSET" }, headers: api_headers
        assert_response :ok
        names = response.parsed_body.map { |a| a["external_name"] }
        assert_includes names, "sunset.jpg"
      end
    end

    test "index search by address field" do
      stub_api_key do
        get api_media_assets_path, params: { q: "San Francisco" }, headers: api_headers
        assert_response :ok
        ids = response.parsed_body.map { |a| a["external_id"] }
        assert_includes ids, "gdrive_file_geo_001"
      end
    end

    test "index search returns empty array for no match" do
      stub_api_key do
        get api_media_assets_path, params: { q: "zzznomatch" }, headers: api_headers
        assert_response :ok
        assert_empty response.parsed_body
      end
    end

    # ===========================================
    # Index — Sorting
    # ===========================================

    test "index default sort is first_seen_at desc" do
      stub_api_key do
        get api_media_assets_path, headers: api_headers
        timestamps = response.parsed_body.map { |a| a["first_seen_at"] }
        assert_equal timestamps.sort.reverse, timestamps
      end
    end

    test "index sorts by file_size asc" do
      stub_api_key do
        get api_media_assets_path, params: { sort: "file_size", direction: "asc" }, headers: api_headers
        assert_response :ok
        sizes = response.parsed_body.map { |a| a["file_size"] }.compact
        assert_equal sizes.sort, sizes
      end
    end

    test "index ignores unknown sort column and uses default" do
      stub_api_key do
        get api_media_assets_path, params: { sort: "malicious; DROP TABLE--" }, headers: api_headers
        assert_response :ok
      end
    end

    # ===========================================
    # Index — Pagination
    # ===========================================

    test "index returns pagination headers" do
      stub_api_key do
        get api_media_assets_path, headers: api_headers
        assert response.headers["X-Total-Count"].present?
        assert response.headers["X-Page"].present?
        assert response.headers["X-Per-Page"].present?
        assert response.headers["X-Total-Pages"].present?
      end
    end

    test "index paginates results" do
      stub_api_key do
        get api_media_assets_path, params: { per_page: 2, page: 1 }, headers: api_headers
        assert_response :ok
        assert_equal 2, response.parsed_body.size
        assert_equal "2", response.headers["X-Per-Page"]
        assert_equal "1", response.headers["X-Page"]
      end
    end

    test "index page 2 returns different results than page 1" do
      stub_api_key do
        get api_media_assets_path, params: { per_page: 2, page: 1, sort: "file_size", direction: "asc" }, headers: api_headers
        page1_ids = response.parsed_body.map { |a| a["id"] }

        get api_media_assets_path, params: { per_page: 2, page: 2, sort: "file_size", direction: "asc" }, headers: api_headers
        page2_ids = response.parsed_body.map { |a| a["id"] }

        assert_empty page1_ids & page2_ids
      end
    end

    test "index caps per_page at 200" do
      stub_api_key do
        get api_media_assets_path, params: { per_page: 9999 }, headers: api_headers
        assert_equal "200", response.headers["X-Per-Page"]
      end
    end

    # ===========================================
    # Show
    # ===========================================

    test "show returns a single asset" do
      stub_api_key do
        asset = media_assets(:sample_image)
        get api_media_asset_path(asset), headers: api_headers
        assert_response :ok
        assert_equal asset.external_id, response.parsed_body["external_id"]
      end
    end

    test "show returns 404 for unknown asset" do
      stub_api_key do
        get api_media_asset_path(99999999), headers: api_headers
        assert_response :not_found
      end
    end

    private

    def api_headers
      { "X-API-AUTH" => @valid_api_key }
    end

    def stub_api_key(&block)
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*args|
        args == [ :api, :key ] ? "test_api_key_12345" : nil
      end
      Rails.application.stub(:credentials, fake_credentials) { yield }
    end
  end
end
