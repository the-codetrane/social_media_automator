require "test_helper"

class MediaAssetFoldersTest < ActiveSupport::TestCase
  test "sanitize trims, drops empty segments and strips surrounding slashes" do
    assert_equal "Gigs/2026", MediaAssetFolders.sanitize(" /Gigs / 2026/ ")
  end

  test "sanitize returns nil for blank or escaping names" do
    assert_nil MediaAssetFolders.sanitize(nil)
    assert_nil MediaAssetFolders.sanitize("   ")
    assert_nil MediaAssetFolders.sanitize("..")
    assert_nil MediaAssetFolders.sanitize("Gigs/../secret")
  end

  test "key_for names the object after the uploaded file" do
    assert_equal "Gigs/White Squirrel 10-15.jpeg",
      MediaAssetFolders.key_for("Gigs", filename: "White Squirrel 10-15.jpeg")
  end

  test "key_for keeps the punctuation already used in the bucket" do
    assert_equal "Gigs/Cain & Co. - Bender Park, Henderson MN 009.jpg",
      MediaAssetFolders.key_for("Gigs", filename: "Cain & Co. - Bender Park, Henderson MN 009.jpg")
  end

  test "key_for strips the directory part and url-hostile characters" do
    assert_equal "Gigs/passwd", MediaAssetFolders.key_for("Gigs", filename: "../../etc/passwd")
    assert_equal "Gigs/a-b.jpg", MediaAssetFolders.key_for("Gigs", filename: "a?b.jpg")
    assert_equal "Gigs/set-1.jpg", MediaAssetFolders.key_for("Gigs", filename: "set#%1.jpg")
  end

  test "key_for falls back to a token when no usable name is left" do
    assert_match %r{\AGigs/[a-z0-9]{28}\z}, MediaAssetFolders.key_for("Gigs", filename: "..")
    assert_match %r{\AGigs/[a-z0-9]{28}\z}, MediaAssetFolders.key_for("Gigs", filename: nil)
  end

  test "key_for suffixes the name when a blob already holds the key" do
    ActiveStorage::Blob.create_before_direct_upload!(
      key: "Gigs/flyer.jpg", filename: "flyer.jpg", byte_size: 1, checksum: "x"
    )

    key = MediaAssetFolders.key_for("Gigs", filename: "flyer.jpg")

    assert_match %r{\AGigs/flyer-[0-9a-f]{6}\.jpg\z}, key
  end

  test "list derives folders from blob keys when the service has no bucket" do
    %w[Gigs/a Gigs/b Map\ Images/c nofolder].each do |key|
      ActiveStorage::Blob.create_before_direct_upload!(key: key, filename: "f", byte_size: 1, checksum: "x")
    end

    assert_equal [ "Gigs", "Map Images" ], MediaAssetFolders.list
  end
end

require "active_storage/service/s3_service"

class MediaAssetFoldersBucketTest < ActiveSupport::TestCase
  test "list reads common prefixes from the bucket on S3-compatible services" do
    service = s3_service(list_objects_v2: { common_prefixes: [ { prefix: "Map Images/" }, { prefix: "Gigs/" } ] })

    ActiveStorage::Blob.stub(:service, service) do
      assert_equal [ "Gigs", "Map Images" ], MediaAssetFolders.list
    end
  end

  # Objects uploaded straight to Spaces have no blob row, so the database alone
  # would not notice the clash and the upload would overwrite them.
  test "key_for suffixes the name when only the bucket holds the key" do
    service = s3_service(head_object: [ {}, "NotFound" ])

    ActiveStorage::Blob.stub(:service, service) do
      assert_match %r{\AGigs/flyer-[0-9a-f]{6}\.jpg\z},
        MediaAssetFolders.key_for("Gigs", filename: "flyer.jpg")
    end
  end

  test "key_for keeps the plain name when the bucket has no such object" do
    service = s3_service(head_object: "NotFound")

    ActiveStorage::Blob.stub(:service, service) do
      assert_equal "Gigs/flyer.jpg", MediaAssetFolders.key_for("Gigs", filename: "flyer.jpg")
    end
  end

  private

  def s3_service(stub_responses)
    ActiveStorage::Service::S3Service.new(
      bucket: "ig-mcp-images", region: "sfo3", access_key_id: "k", secret_access_key: "s",
      public: true, stub_responses: stub_responses
    )
  end
end
