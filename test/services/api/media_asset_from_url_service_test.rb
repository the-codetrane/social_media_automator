# frozen_string_literal: true

require "test_helper"

module Api
  class MediaAssetFromUrlServiceTest < ActiveSupport::TestCase
    # ===========================================
    # URL Validation Tests
    # ===========================================

    test "returns false for nil url" do
      service = MediaAssetFromUrlService.new(nil)
      assert_not service.call
      assert_equal "Invalid URL format", service.error
    end

    test "returns false for empty string url" do
      service = MediaAssetFromUrlService.new("")
      assert_not service.call
      assert_equal "Invalid URL format", service.error
    end

    test "returns false for invalid url format" do
      service = MediaAssetFromUrlService.new("not-a-url")
      assert_not service.call
      assert_equal "Invalid URL format", service.error
    end

    test "returns false for ftp url" do
      service = MediaAssetFromUrlService.new("ftp://example.com/file.mp4")
      assert_not service.call
      assert_equal "Invalid URL format", service.error
    end

    test "accepts http url" do
      service = MediaAssetFromUrlService.new("http://example.com/video.mp4")
      assert service.call
      assert service.success?
    end

    test "accepts https url" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
      assert service.call
      assert service.success?
    end

    # ===========================================
    # Media Asset Creation Tests
    # ===========================================

    test "creates media asset from valid url" do
      url = "https://spaces.digitalocean.com/bucket/my-video.mp4"

      assert_difference("MediaAsset.count", 1) do
        service = MediaAssetFromUrlService.new(url)
        assert service.call
      end
    end

    test "sets external_id based on url hash" do
      url = "https://spaces.digitalocean.com/bucket/video.mp4"
      service = MediaAssetFromUrlService.new(url)
      service.call

      expected_id = "api_#{Digest::SHA256.hexdigest(url)[0, 16]}"
      assert_equal expected_id, service.media_asset.external_id
    end

    test "sets external_name from filename" do
      url = "https://spaces.digitalocean.com/bucket/my-awesome-video.mp4"
      service = MediaAssetFromUrlService.new(url)
      service.call

      assert_equal "my-awesome-video.mp4", service.media_asset.external_name
    end

    test "sets status to discovered" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
      service.call

      assert_equal "discovered", service.media_asset.status
    end

    test "sets first_seen_at to current time" do
      freeze_time do
        service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
        service.call

        assert_equal Time.current, service.media_asset.first_seen_at
      end
    end

    test "stores url in raw_metadata" do
      url = "https://spaces.digitalocean.com/bucket/video.mp4"
      service = MediaAssetFromUrlService.new(url)
      service.call

      metadata = JSON.parse(service.media_asset.raw_metadata)
      assert_equal url, metadata["public_url"]
      assert_equal "api", metadata["source"]
    end

    # ===========================================
    # Media Type Detection Tests
    # ===========================================

    test "detects jpg as image" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.jpg")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects jpeg as image" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.jpeg")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects png as image" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.png")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects gif as image" do
      service = MediaAssetFromUrlService.new("https://example.com/animation.gif")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects webp as image" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.webp")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects heic as image" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.heic")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    test "detects mp4 as video" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "detects mov as video" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mov")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "detects avi as video" do
      service = MediaAssetFromUrlService.new("https://example.com/video.avi")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "detects webm as video" do
      service = MediaAssetFromUrlService.new("https://example.com/video.webm")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "detects m4v as video" do
      service = MediaAssetFromUrlService.new("https://example.com/video.m4v")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "defaults to video for unknown extension" do
      service = MediaAssetFromUrlService.new("https://example.com/file.unknown")
      service.call
      assert_equal "video", service.media_asset.media_type
    end

    test "handles uppercase extensions" do
      service = MediaAssetFromUrlService.new("https://example.com/photo.JPG")
      service.call
      assert_equal "image", service.media_asset.media_type
    end

    # ===========================================
    # Duplicate Detection Tests
    # ===========================================

    test "reuses existing media asset for same url" do
      url = "https://spaces.digitalocean.com/bucket/existing.mp4"

      # Create first media asset
      first_service = MediaAssetFromUrlService.new(url)
      first_service.call
      first_asset = first_service.media_asset

      # Second call should reuse existing
      assert_no_difference("MediaAsset.count") do
        second_service = MediaAssetFromUrlService.new(url)
        assert second_service.call
        assert_equal first_asset.id, second_service.media_asset.id
      end
    end

    test "creates new asset for different url" do
      first_service = MediaAssetFromUrlService.new("https://example.com/video1.mp4")
      first_service.call

      assert_difference("MediaAsset.count", 1) do
        second_service = MediaAssetFromUrlService.new("https://example.com/video2.mp4")
        second_service.call
      end
    end

    # ===========================================
    # Edge Cases Tests
    # ===========================================

    test "handles url with query parameters" do
      url = "https://example.com/video.mp4?token=abc123&expires=999"
      service = MediaAssetFromUrlService.new(url)
      assert service.call

      assert_equal "video.mp4", service.media_asset.external_name
      assert_equal "video", service.media_asset.media_type
    end

    test "handles url with special characters in filename" do
      url = "https://example.com/my%20video%20file.mp4"
      service = MediaAssetFromUrlService.new(url)
      assert service.call

      assert_equal "my%20video%20file.mp4", service.media_asset.external_name
    end

    test "handles url without file extension" do
      url = "https://example.com/media/12345"
      service = MediaAssetFromUrlService.new(url)
      assert service.call

      # Should default to video
      assert_equal "video", service.media_asset.media_type
    end

    test "success? returns true after successful call" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
      service.call

      assert service.success?
      assert_nil service.error
      assert_not_nil service.media_asset
    end

    test "success? returns false after failed call" do
      service = MediaAssetFromUrlService.new("invalid-url")
      service.call

      assert_not service.success?
      assert_not_nil service.error
      assert_nil service.media_asset
    end

    # ===========================================
    # Spaces deduplication
    # ===========================================

    test "reuses the asset for one Spaces object reached through differently spelled urls" do
      urls = [
        "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com/Eagle's%2034/Clip%201.mp4",
        "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com/Eagle%27s%2034/Clip%201.mp4",
        "https://ig-mcp-images.sfo3.digitaloceanspaces.com/Eagle%27s%2034/Clip%201.mp4",
        "https://sfo3.digitaloceanspaces.com/ig-mcp-images/Eagle's%2034/Clip%201.mp4?x=1"
      ]

      assets = nil
      assert_difference("MediaAsset.count", 1) do
        assets = urls.map { |u| MediaAssetFromUrlService.new(u).tap(&:call).media_asset }
      end

      assert_equal 1, assets.map(&:id).uniq.size
      assert_equal "Eagle's 34/Clip 1.mp4", assets.first.storage_key
    end

    test "reuses an asset that was registered by the Spaces sync" do
      existing = MediaAsset.create!(
        external_id: "sync_whatever", media_type: :video, status: :discovered, first_seen_at: Time.current,
        storage_key: "Car Promo/IMG_0001.mov"
      )

      service = MediaAssetFromUrlService.new("https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com/Car%20Promo/IMG_0001.mov")
      assert_no_difference("MediaAsset.count") { assert service.call }
      assert_equal existing, service.media_asset
    end

    test "matches legacy rows whose key is only in raw_metadata" do
      legacy = MediaAsset.create!(
        external_id: "api_legacy", media_type: :image, status: :processed, first_seen_at: Time.current,
        raw_metadata: { public_url: "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com/Porchfest/a%20b.jpg", source: "api" }.to_json
      )
      assert_equal "Porchfest/a b.jpg", legacy.storage_key

      service = MediaAssetFromUrlService.new("https://ig-mcp-images.sfo3.digitaloceanspaces.com/Porchfest/a%20b.jpg?v=1")
      assert_no_difference("MediaAsset.count") { assert service.call }
      assert_equal legacy, service.media_asset
    end

    test "leaves storage_key blank for urls outside the bucket" do
      service = MediaAssetFromUrlService.new("https://example.com/video.mp4")
      assert service.call
      assert_nil service.media_asset.storage_key
    end
  end
end
