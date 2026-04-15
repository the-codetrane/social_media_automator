# frozen_string_literal: true

require "test_helper"

module Api
  class PlannedPostsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      @media_asset = media_assets(:sample_image)
      @social_template = social_templates(:instagram_default)
      @valid_api_key = "test_api_key_12345"
    end

    # ===========================================
    # Authentication Tests
    # ===========================================

    test "create returns unauthorized without API key" do
      post api_planned_posts_path, params: { planned_post: valid_params }
      assert_response :unauthorized
      assert_equal({ "error" => "Missing API key" }, response.parsed_body)
    end

    test "create returns unauthorized with invalid API key" do
      stub_api_key do
        post api_planned_posts_path,
             params: { planned_post: valid_params },
             headers: { "X-API-AUTH" => "invalid_key" }
        assert_response :unauthorized
        assert_equal({ "error" => "Invalid API key" }, response.parsed_body)
      end
    end

    test "create succeeds with valid API key" do
      stub_api_key do
        post api_planned_posts_path,
             params: { planned_post: valid_params },
             headers: api_headers
        assert_response :created
      end
    end

    # ===========================================
    # Create Action Tests (with media_asset_id)
    # ===========================================

    test "create with media_asset_id creates planned post" do
      stub_api_key do
        assert_difference("PlannedPost.count", 1) do
          post api_planned_posts_path,
               params: { planned_post: valid_params },
               headers: api_headers
        end

        assert_response :created
        json = response.parsed_body
        assert_equal @user.id, json["user_id"]
        assert_equal @media_asset.id, json["media_asset_id"]
        assert_equal "instagram", json["platform"]
        assert_equal "draft", json["status"]
        assert_equal "Test caption", json["caption"]
      end
    end

    test "create with scheduled status requires scheduled_at" do
      stub_api_key do
        params = valid_params.merge(status: "scheduled", scheduled_at: nil)

        assert_no_difference("PlannedPost.count") do
          post api_planned_posts_path,
               params: { planned_post: params },
               headers: api_headers
        end

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Scheduled at can't be blank"
      end
    end

    test "create with scheduled status and future date succeeds" do
      stub_api_key do
        params = valid_params.merge(status: "scheduled", scheduled_at: 2.days.from_now.iso8601)

        assert_difference("PlannedPost.count", 1) do
          post api_planned_posts_path,
               params: { planned_post: params },
               headers: api_headers
        end

        assert_response :created
        assert_equal "scheduled", response.parsed_body["status"]
      end
    end

    test "create with invalid user_id fails" do
      stub_api_key do
        params = valid_params.merge(user_id: 999999)

        assert_no_difference("PlannedPost.count") do
          post api_planned_posts_path,
               params: { planned_post: params },
               headers: api_headers
        end

        assert_response :unprocessable_entity
      end
    end

    test "create with invalid media_asset_id fails" do
      stub_api_key do
        params = valid_params.merge(media_asset_id: 999999)

        assert_no_difference("PlannedPost.count") do
          post api_planned_posts_path,
               params: { planned_post: params },
               headers: api_headers
        end

        assert_response :unprocessable_entity
      end
    end

    test "create with optional social_template_id" do
      stub_api_key do
        params = valid_params.merge(social_template_id: @social_template.id)

        post api_planned_posts_path,
             params: { planned_post: params },
             headers: api_headers

        assert_response :created
        assert_equal @social_template.id, response.parsed_body["social_template_id"]
      end
    end

    test "create includes all expected response fields" do
      stub_api_key do
        post api_planned_posts_path,
             params: { planned_post: valid_params },
             headers: api_headers

        json = response.parsed_body
        expected_keys = %w[id user_id media_asset_id social_template_id platform status caption hashtags scheduled_at created_at updated_at]
        assert_equal expected_keys.sort, json.keys.sort
      end
    end

    # ===========================================
    # Create Action Tests (with media_url)
    # ===========================================

    test "create with media_url creates media asset and planned post" do
      stub_api_key do
        media_url = "https://spaces.digitalocean.com/bucket/video.mp4"

        assert_difference([ "PlannedPost.count", "MediaAsset.count" ], 1) do
          post api_planned_posts_path,
               params: { planned_post: valid_params_with_url(media_url) },
               headers: api_headers
        end

        assert_response :created
        json = response.parsed_body
        assert_not_nil json["media_asset_id"]

        # Verify media asset was created correctly
        media_asset = MediaAsset.find(json["media_asset_id"])
        assert_equal "video", media_asset.media_type
        assert_equal "discovered", media_asset.status
        assert_equal "video.mp4", media_asset.external_name
      end
    end

    test "create with media_url for image detects image type" do
      stub_api_key do
        media_url = "https://spaces.digitalocean.com/bucket/photo.jpg"

        post api_planned_posts_path,
             params: { planned_post: valid_params_with_url(media_url) },
             headers: api_headers

        assert_response :created
        media_asset = MediaAsset.find(response.parsed_body["media_asset_id"])
        assert_equal "image", media_asset.media_type
      end
    end

    test "create with same media_url reuses existing media asset" do
      stub_api_key do
        media_url = "https://spaces.digitalocean.com/bucket/reusable.mp4"

        # First request creates the media asset
        post api_planned_posts_path,
             params: { planned_post: valid_params_with_url(media_url) },
             headers: api_headers
        first_media_asset_id = response.parsed_body["media_asset_id"]

        # Second request should reuse the same media asset
        assert_difference("PlannedPost.count", 1) do
          assert_no_difference("MediaAsset.count") do
            post api_planned_posts_path,
                 params: { planned_post: valid_params_with_url(media_url) },
                 headers: api_headers
          end
        end

        assert_equal first_media_asset_id, response.parsed_body["media_asset_id"]
      end
    end

    test "create with invalid media_url returns error" do
      stub_api_key do
        post api_planned_posts_path,
             params: { planned_post: valid_params_with_url("not-a-valid-url") },
             headers: api_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"].first, "Media asset error"
      end
    end

    test "create without media_asset_id or media_url fails validation" do
      stub_api_key do
        params = valid_params.except(:media_asset_id)

        post api_planned_posts_path,
             params: { planned_post: params },
             headers: api_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Media asset must exist"
      end
    end

    # ===========================================
    # Bulk Create Action Tests
    # ===========================================

    test "bulk_create returns unauthorized without API key" do
      post bulk_create_api_planned_posts_path, params: { planned_posts: [ valid_params ] }
      assert_response :unauthorized
    end

    test "bulk_create creates multiple planned posts" do
      stub_api_key do
        params = [
          valid_params,
          valid_params.merge(caption: "Second post", platform: "youtube")
        ]

        assert_difference("PlannedPost.count", 2) do
          post bulk_create_api_planned_posts_path,
               params: { planned_posts: params },
               headers: api_headers
        end

        assert_response :created
        json = response.parsed_body
        assert_equal 2, json["created"].length
        assert_empty json["errors"]
      end
    end

    test "bulk_create with media_url creates media assets" do
      stub_api_key do
        params = [
          valid_params_with_url("https://spaces.digitalocean.com/bucket/video1.mp4"),
          valid_params_with_url("https://spaces.digitalocean.com/bucket/video2.mp4")
        ]

        assert_difference("PlannedPost.count", 2) do
          assert_difference("MediaAsset.count", 2) do
            post bulk_create_api_planned_posts_path,
                 params: { planned_posts: params },
                 headers: api_headers
          end
        end

        assert_response :created
      end
    end

    test "bulk_create with partial failures returns multi_status" do
      stub_api_key do
        params = [
          valid_params,
          valid_params.merge(user_id: 999999) # Invalid user
        ]

        assert_difference("PlannedPost.count", 1) do
          post bulk_create_api_planned_posts_path,
               params: { planned_posts: params },
               headers: api_headers
        end

        assert_response :multi_status
        json = response.parsed_body
        assert_equal 1, json["created"].length
        assert_equal 1, json["errors"].length
        assert_equal 1, json["errors"].first["index"]
      end
    end

    test "bulk_create with invalid media_url includes error with index" do
      stub_api_key do
        params = [
          valid_params,
          valid_params_with_url("invalid-url")
        ]

        post bulk_create_api_planned_posts_path,
             params: { planned_posts: params },
             headers: api_headers

        assert_response :multi_status
        json = response.parsed_body
        assert_equal 1, json["created"].length
        assert_equal 1, json["errors"].length
        assert_equal 1, json["errors"].first["index"]
        assert_includes json["errors"].first["errors"].first, "Media asset error"
      end
    end

    test "bulk_create with all failures still returns multi_status" do
      stub_api_key do
        params = [
          valid_params.merge(user_id: 999999),
          valid_params.merge(user_id: 999998)
        ]

        assert_no_difference("PlannedPost.count") do
          post bulk_create_api_planned_posts_path,
               params: { planned_posts: params },
               headers: api_headers
        end

        assert_response :multi_status
        json = response.parsed_body
        assert_empty json["created"]
        assert_equal 2, json["errors"].length
      end
    end

    test "bulk_create error response excludes sensitive params" do
      stub_api_key do
        params = [
          valid_params.merge(user_id: 999999)
        ]

        post bulk_create_api_planned_posts_path,
             params: { planned_posts: params },
             headers: api_headers

        json = response.parsed_body
        assert_not_includes json["errors"].first["params"].keys, "user_id"
        assert_not_includes json["errors"].first["params"].keys, "media_url"
      end
    end

    private

    def api_headers
      { "X-API-AUTH" => @valid_api_key }
    end

    def valid_params
      {
        user_id: @user.id,
        media_asset_id: @media_asset.id,
        platform: "instagram",
        status: "draft",
        caption: "Test caption",
        hashtags: "#test #api"
      }
    end

    def valid_params_with_url(url)
      {
        user_id: @user.id,
        media_url: url,
        platform: "instagram",
        status: "draft",
        caption: "Test caption from URL",
        hashtags: "#test #api"
      }
    end

    def stub_api_key(&block)
      # Create a credentials object that returns the valid API key
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*args|
        if args == [ :api, :key ]
          "test_api_key_12345"
        else
          nil
        end
      end

      Rails.application.stub(:credentials, fake_credentials) do
        yield
      end
    end
  end
end
