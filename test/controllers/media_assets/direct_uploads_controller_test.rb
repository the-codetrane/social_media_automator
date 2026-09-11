require "test_helper"

class MediaAssets::DirectUploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @blob_params = { blob: { filename: "gig.jpg", byte_size: 1234, checksum: "abc==", content_type: "image/jpeg" } }
  end

  test "requires authentication" do
    post media_assets_direct_uploads_path(folder: "Gigs"), params: @blob_params, as: :json
    assert_redirected_to new_session_path
  end

  test "creates a blob keyed under the requested folder" do
    sign_in_as(@user)

    assert_difference "ActiveStorage::Blob.count", 1 do
      post media_assets_direct_uploads_path(folder: " Gigs/2026 "), params: @blob_params, as: :json
    end

    assert_response :success
    body = response.parsed_body
    blob = ActiveStorage::Blob.find_signed!(body["signed_id"])
    assert_match %r{\AGigs/2026/[a-z0-9]+\z}, blob.key
    assert_equal "gig.jpg", blob.filename.to_s
    assert body.dig("direct_upload", "url").present?
  end

  test "rejects a missing folder" do
    sign_in_as(@user)
    assert_no_difference "ActiveStorage::Blob.count" do
      post media_assets_direct_uploads_path, params: @blob_params, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "rejects a folder that tries to escape" do
    sign_in_as(@user)
    assert_no_difference "ActiveStorage::Blob.count" do
      post media_assets_direct_uploads_path(folder: "../etc"), params: @blob_params, as: :json
    end
    assert_response :unprocessable_entity
  end
end
