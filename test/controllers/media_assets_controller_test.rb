require "test_helper"

class MediaAssetsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @media_asset = media_assets(:sample_image)
  end

  test "index redirects when not signed in" do
    get media_assets_path(availability: "all")
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_response :success
  end

  test "index lists all assets" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_match "sunset.jpg", response.body
    assert_match "reel.mp4", response.body
  end

  test "index shows media type badges" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_match "image", response.body
    assert_match "video", response.body
  end

  test "index shows status badges" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_match "processed", response.body
  end

  test "index shows file size" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_match "1.95 MB", response.body
  end

  test "index shows video duration" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_match "31s", response.body
  end

  test "index displays image thumbnail preview" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_select "img[src=?]", @media_asset.public_url
  end

  test "index displays video thumbnail preview" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    video_asset = media_assets(:sample_video)
    assert_select "video source[src=?]", video_asset.public_url
  end

  test "index displays placeholder when no public url" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    # Should have placeholder SVG for assets without public URL
    assert_select "svg"
  end

  # Show action tests
  test "show redirects when not signed in" do
    get media_asset_path(@media_asset)
    assert_redirected_to new_session_path
  end

  test "show returns success when signed in" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_response :success
  end

  test "show displays asset details" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_match @media_asset.external_name, response.body
    assert_match @media_asset.media_type, response.body
  end

  test "show has edit link" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "a[href=?]", edit_media_asset_path(@media_asset)
  end

  test "show has back link to index" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "a[href=?]", media_assets_path
  end

  test "show displays dimensions" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_match "#{@media_asset.width}", response.body
    assert_match "#{@media_asset.height}", response.body
  end

  test "show displays image media preview" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_select "img[src=?]", @media_asset.public_url
  end

  test "show displays video media preview" do
    sign_in_as(@user)
    video_asset = media_assets(:sample_video)
    get media_asset_path(video_asset)
    assert_select "video" do
      assert_select "source[src=?]", video_asset.public_url
    end
  end

  test "show does not display media preview when no public url" do
    sign_in_as(@user)
    asset_no_url = media_assets(:sample_image_no_url)
    get media_asset_path(asset_no_url)
    assert_response :success
    # Scoped to main: the nav carries the site logo as an <img>.
    assert_select "main img", count: 0
    assert_select "main video", count: 0
  end

  # Edit action tests
  test "edit redirects when not signed in" do
    get edit_media_asset_path(@media_asset)
    assert_redirected_to new_session_path
  end

  test "edit returns success when signed in" do
    sign_in_as(@user)
    get edit_media_asset_path(@media_asset)
    assert_response :success
  end

  test "edit displays form with current values" do
    sign_in_as(@user)
    get edit_media_asset_path(@media_asset)
    assert_select "input[name='media_asset[external_name]'][value=?]", @media_asset.external_name
    assert_select "select[name='media_asset[status]']"
  end

  # Update action tests
  test "update redirects when not signed in" do
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "New Name" } }
    assert_redirected_to new_session_path
  end

  test "update changes asset attributes" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "updated_image.jpg" } }
    assert_redirected_to media_asset_path(@media_asset)
    @media_asset.reload
    assert_equal "updated_image.jpg", @media_asset.external_name
  end

  test "update can change status" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { status: "failed" } }
    assert_redirected_to media_asset_path(@media_asset)
    @media_asset.reload
    assert_equal "failed", @media_asset.status
  end

  test "update shows success notice" do
    sign_in_as(@user)
    patch media_asset_path(@media_asset), params: { media_asset: { external_name: "new.jpg" } }
    follow_redirect!
    assert_match "successfully updated", response.body
  end

  # URL decoding tests
  test "index decodes URL-encoded names" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    # Should show decoded name, not URL-encoded
    assert_match "Big Guys BBQ", response.body
    assert_no_match(/%20/, response.body.scan(/Big.*BBQ/).first || "")
  end

  test "show decodes URL-encoded name in heading" do
    sign_in_as(@user)
    url_encoded_asset = media_assets(:url_encoded_name)
    get media_asset_path(url_encoded_asset)
    assert_match "Big Guys BBQ", response.body
    # The h1 should contain decoded name
    assert_select "h1", text: /Big Guys BBQ/
  end

  test "show decodes URL-encoded name in title" do
    sign_in_as(@user)
    url_encoded_asset = media_assets(:url_encoded_name)
    get media_asset_path(url_encoded_asset)
    assert_select "title", text: /Big Guys BBQ/
  end

  # Geocoding / location section
  test "show renders address for geocoded asset" do
    sign_in_as(@user)
    get media_asset_path(media_assets(:geocoded_image))
    assert_match "San Francisco, CA, USA", response.body
  end

  test "show does not render location section for non-geocoded asset" do
    sign_in_as(@user)
    get media_asset_path(@media_asset)
    assert_no_match "Map unavailable", response.body
    assert_select "iframe", count: 0
  end

  test "show renders pending state when static map image not yet fetched" do
    sign_in_as(@user)
    get media_asset_path(media_assets(:geocoded_image))
    assert_match "Map image pending", response.body
    assert_select "iframe", count: 0
  end

  test "show renders static map image when attached" do
    sign_in_as(@user)
    asset = media_assets(:geocoded_image)
    asset.static_map_image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "static_map.png",
      content_type: "image/png"
    )
    get media_asset_path(asset)
    assert_select "img[alt=?]", "Map"
  end

  # ── Upload modal ────────────────────────────────────────────────────────

  test "index renders the upload CTA and modal frame" do
    sign_in_as(@user)
    get media_assets_path(availability: "all")
    assert_select "a[href=?][data-turbo-frame=media-upload-modal]", new_media_asset_path, text: /Upload media/
    assert_select "dialog[data-controller=modal] turbo-frame#media-upload-modal"
  end

  test "new renders the upload form inside the modal frame with existing folders" do
    ActiveStorage::Blob.create_before_direct_upload!(
      key: "Gigs/abc123", filename: "a.jpg", byte_size: 10, checksum: "x", content_type: "image/jpeg"
    )
    sign_in_as(@user)
    get new_media_asset_path
    assert_response :success
    assert_select "turbo-frame#media-upload-modal form[data-controller=media-upload]"
    assert_select "select[name='media_asset[folder]'] option[value=Gigs]"
    assert_select "select[name='media_asset[folder]'] option[value=__new__]"
    assert_select "input[type=file][name='media_asset[files][]'][multiple][accept='image/*,video/*']"
  end

  test "create builds a media asset per uploaded blob and enqueues analysis" do
    sign_in_as(@user)
    image = ActiveStorage::Blob.create_and_upload!(io: file_fixture("test_image.png").open, filename: "gig.png", content_type: "image/png", key: "Gigs/img1")
    video = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("not really a video"), filename: "gig.mp4", content_type: "video/mp4", key: "Gigs/vid1")

    assert_difference "MediaAsset.count", 2 do
      assert_enqueued_jobs 2, only: AnalyzeMediaAssetJob do
        post media_assets_path, params: { media_asset: { signed_ids: [ image.signed_id, video.signed_id ] } }
      end
    end

    assert_redirected_to media_assets_path
    assert_equal "2 files uploaded.", flash[:notice]

    png = MediaAsset.find_by!(external_name: "gig.png")
    assert png.image?
    assert png.processed?
    assert_equal "image/png", png.mime_type
    assert_equal image.byte_size, png.file_size
    assert_equal image, png.file.blob

    mp4 = MediaAsset.find_by!(external_name: "gig.mp4")
    assert mp4.video?
    assert_equal video, mp4.file.blob
  end

  test "create ignores invalid signed ids and re-renders the form" do
    sign_in_as(@user)
    assert_no_difference "MediaAsset.count" do
      post media_assets_path, params: { media_asset: { signed_ids: [ "garbage" ] } }
    end
    assert_response :unprocessable_entity
    assert_match "Select at least one photo or video", response.body
  end

  test "create requires authentication" do
    post media_assets_path, params: { media_asset: { signed_ids: [ "x" ] } }
    assert_redirected_to new_session_path
  end
  # --- Archive / availability ------------------------------------------------

  test "index defaults to available assets only" do
    sign_in_as(@user)
    media_assets(:geocoded_image).archive!

    get media_assets_path

    assert_response :success
    assert_no_match "sf_photo.jpg", response.body  # archived
    assert_no_match "sunset.jpg", response.body    # on a scheduled fixture post
    assert_match "sunrise.jpg", response.body      # unused
  end

  test "index can filter to archived assets" do
    sign_in_as(@user)
    media_assets(:geocoded_image).archive!

    get media_assets_path(availability: "archived")

    assert_match "sf_photo.jpg", response.body
    assert_no_match "sunrise.jpg", response.body
  end

  test "index can filter to published assets" do
    sign_in_as(@user)
    media_assets(:sample_image_2).update!(published_at: 1.day.ago)

    get media_assets_path(availability: "published")

    assert_match "sunrise.jpg", response.body
    assert_match "Published", response.body
  end

  test "archive soft-deletes and unarchive restores" do
    sign_in_as(@user)

    patch archive_media_asset_path(@media_asset)
    assert_redirected_to media_asset_path(@media_asset)
    assert @media_asset.reload.archived?

    patch unarchive_media_asset_path(@media_asset)
    assert_not @media_asset.reload.archived?
  end

  test "archive requires sign in" do
    patch archive_media_asset_path(@media_asset)
    assert_redirected_to new_session_path
    assert_not @media_asset.reload.archived?
  end

  test "bulk_archive and bulk_unarchive act on the selected ids" do
    sign_in_as(@user)
    ids = [ media_assets(:sample_image_2).id, media_assets(:geocoded_image).id ]

    patch bulk_archive_media_assets_path, params: { ids: ids }
    assert_redirected_to media_assets_path
    assert_equal 2, MediaAsset.archived.where(id: ids).count

    patch bulk_unarchive_media_assets_path, params: { ids: ids }
    assert_equal 0, MediaAsset.archived.where(id: ids).count
  end

  test "show lists posts that use the asset, including carousels" do
    sign_in_as(@user)
    get media_asset_path(media_assets(:sample_image_2))

    assert_response :success
    assert_match "Used in posts", response.body
    assert_match planned_post_path(planned_posts(:carousel_post)), response.body
  end
end
