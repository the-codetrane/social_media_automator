# frozen_string_literal: true

require "test_helper"

module GoogleDrive
  class FileSyncServiceTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def setup
      @drive = connected_drives(:secondary_drive)  # last_synced_at: nil → due for sync
    end

    # Build a minimal file hash the way the Drive API returns it.
    def drive_file(id:, name:, mime_type:, size: "102400",
                   web_view_link: "https://drive.google.com/file/d/#{id}/view",
                   web_content_link: "https://drive.google.com/uc?id=#{id}",
                   thumbnail_link: nil,
                   image_metadata: nil)
      {
        "id"                 => id,
        "name"               => name,
        "mimeType"           => mime_type,
        "size"               => size,
        "webViewLink"        => web_view_link,
        "webContentLink"     => web_content_link,
        "thumbnailLink"      => thumbnail_link,
        "imageMediaMetadata" => image_metadata,
        "createdTime"        => "2026-01-15T10:00:00.000Z"
      }.compact
    end

    # Return a stub client whose list_files yields pages in sequence.
    # pages is an Array of file arrays; each entry is one page.
    def stub_client_for_pages(folder_id, pages)
      page_responses = pages.each_with_index.map do |files, idx|
        next_token = idx < pages.length - 1 ? "page_token_#{idx + 1}" : nil
        { "files" => files, "nextPageToken" => next_token }
      end

      call_count = -1
      client = Object.new
      client.define_singleton_method(:list_files) do |_folder_id, page_token: nil|
        call_count += 1
        page_responses[call_count]
      end
      client
    end

    def with_mock_client(pages)
      client = stub_client_for_pages(@drive.folder_id, pages)
      GoogleDrive::ApiClient.stub(:new, client) do
        yield GoogleDrive::FileSyncService.new(@drive)
      end
    end

    # -------------------------------------------------------------------------
    # Basic upsert behaviour
    # -------------------------------------------------------------------------

    test "call creates a MediaAsset for a supported image file" do
      file = drive_file(id: "img_new_001", name: "beach.jpg", mime_type: "image/jpeg",
                        image_metadata: { "width" => 4032, "height" => 3024 })

      with_mock_client([ [ file ] ]) do |service|
        assert_difference "MediaAsset.count", 1 do
          service.call
        end
      end

      asset = MediaAsset.find_by!(external_id: "img_new_001")
      assert_equal "beach.jpg",   asset.external_name
      assert_equal "image/jpeg",  asset.mime_type
      assert       asset.image?
      assert_equal 4032,          asset.width
      assert_equal 3024,          asset.height
      assert_equal 102400,        asset.file_size
      assert_equal "discovered",  asset.status
    end

    test "call creates a MediaAsset for a supported video file" do
      file = drive_file(id: "vid_new_001", name: "reel.mp4", mime_type: "video/mp4", size: "52428800")

      with_mock_client([ [ file ] ]) do |service|
        assert_difference "MediaAsset.count", 1 do
          service.call
        end
      end

      asset = MediaAsset.find_by!(external_id: "vid_new_001")
      assert asset.video?
      assert_equal "video/mp4", asset.mime_type
    end

    test "call stores web_view_link and web_content_link in raw_metadata" do
      file = drive_file(
        id: "img_meta_001", name: "meta.jpg", mime_type: "image/jpeg",
        web_view_link: "https://drive.google.com/file/d/img_meta_001/view",
        web_content_link: "https://drive.google.com/uc?id=img_meta_001"
      )

      with_mock_client([ [ file ] ]) do |service|
        service.call
      end

      asset = MediaAsset.find_by!(external_id: "img_meta_001")
      assert_equal "https://drive.google.com/file/d/img_meta_001/view",  asset.raw_metadata["web_view_link"]
      assert_equal "https://drive.google.com/uc?id=img_meta_001",        asset.raw_metadata["web_content_link"]
    end

    # -------------------------------------------------------------------------
    # MIME type filtering
    # -------------------------------------------------------------------------

    test "call skips Google Workspace document types" do
      unsupported_files = [
        drive_file(id: "doc1",   name: "Notes.gdoc",   mime_type: "application/vnd.google-apps.document"),
        drive_file(id: "sheet1", name: "Budget.gsheet", mime_type: "application/vnd.google-apps.spreadsheet"),
        drive_file(id: "pdf1",   name: "Report.pdf",   mime_type: "application/pdf")
      ]

      with_mock_client([ unsupported_files ]) do |service|
        assert_no_difference "MediaAsset.count" do
          result = service.call
          assert_equal 0, result[:synced]
          assert_equal 3, result[:skipped]
        end
      end
    end

    test "call returns correct synced and skipped counts for mixed files" do
      files = [
        drive_file(id: "img_mix_001", name: "photo.jpg",  mime_type: "image/jpeg"),
        drive_file(id: "img_mix_002", name: "photo.png",  mime_type: "image/png"),
        drive_file(id: "doc_mix_001", name: "notes.gdoc", mime_type: "application/vnd.google-apps.document")
      ]

      with_mock_client([ files ]) do |service|
        result = service.call
        assert_equal 2, result[:synced]
        assert_equal 1, result[:skipped]
      end
    end

    # -------------------------------------------------------------------------
    # Pagination
    # -------------------------------------------------------------------------

    test "call pages through all results when nextPageToken is present" do
      page1 = [ drive_file(id: "pg_img_001", name: "p1.jpg", mime_type: "image/jpeg") ]
      page2 = [ drive_file(id: "pg_img_002", name: "p2.jpg", mime_type: "image/jpeg") ]
      page3 = [ drive_file(id: "pg_img_003", name: "p3.jpg", mime_type: "image/jpeg") ]

      with_mock_client([ page1, page2, page3 ]) do |service|
        result = service.call
        assert_equal 3, result[:synced]
      end

      assert MediaAsset.exists?(external_id: "pg_img_001")
      assert MediaAsset.exists?(external_id: "pg_img_002")
      assert MediaAsset.exists?(external_id: "pg_img_003")
    end

    # -------------------------------------------------------------------------
    # Upsert / idempotency
    # -------------------------------------------------------------------------

    test "call updates metadata of an existing MediaAsset without creating duplicates" do
      existing = media_assets(:sample_image)  # external_id: "gdrive_file_001", status: :processed

      file = drive_file(
        id:              existing.external_id,
        name:            "sunset_renamed.jpg",
        mime_type:       "image/jpeg",
        size:            "3145728",
        image_metadata:  { "width" => 3024, "height" => 4032 }
      )

      with_mock_client([ [ file ] ]) do |service|
        assert_no_difference "MediaAsset.count" do
          service.call
        end
      end

      existing.reload
      assert_equal "sunset_renamed.jpg", existing.external_name
      assert_equal 3_145_728,            existing.file_size
      assert_equal 3024,                 existing.width
    end

    test "call preserves the status of an existing processed MediaAsset" do
      existing = media_assets(:sample_image)
      assert existing.processed?, "Fixture precondition: status should be :processed"

      file = drive_file(id: existing.external_id, name: existing.external_name, mime_type: "image/jpeg")

      with_mock_client([ [ file ] ]) do |service|
        service.call
      end

      assert existing.reload.processed?, "Status should remain :processed after sync"
    end

    test "call preserves first_seen_at for existing assets" do
      existing     = media_assets(:sample_image)
      original_fsa = existing.first_seen_at

      file = drive_file(id: existing.external_id, name: existing.external_name, mime_type: "image/jpeg")

      with_mock_client([ [ file ] ]) do |service|
        service.call
      end

      assert_equal original_fsa.to_i, existing.reload.first_seen_at.to_i
    end

    # -------------------------------------------------------------------------
    # last_synced_at update
    # -------------------------------------------------------------------------

    test "call updates last_synced_at on the ConnectedDrive record" do
      with_mock_client([ [] ]) do |service|
        freeze_time do
          service.call
          assert_in_delta Time.current.to_i, @drive.reload.last_synced_at.to_i, 2
        end
      end
    end

    # -------------------------------------------------------------------------
    # Robustness
    # -------------------------------------------------------------------------

    test "call logs and skips a file that fails MediaAsset validation" do
      # size "0" → file_size: 0 which violates `validates :file_size, numericality: { greater_than: 0 }`
      bad_file = drive_file(id: "bad_size_001", name: "zero_byte.jpg", mime_type: "image/jpeg", size: "0")

      with_mock_client([ [ bad_file ] ]) do |service|
        assert_no_difference "MediaAsset.count" do
          result = service.call
          assert_equal 0, result[:synced]
          assert_equal 1, result[:skipped]
        end
      end
    end
  end
end
