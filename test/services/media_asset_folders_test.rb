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

  test "key_for nests a unique token under the folder" do
    assert_match %r{\AGigs/[a-z0-9]{28}\z}, MediaAssetFolders.key_for("Gigs")
  end

  test "list derives folders from blob keys when the service has no bucket" do
    %w[Gigs/a Gigs/b Map\ Images/c nofolder].each do |key|
      ActiveStorage::Blob.create_before_direct_upload!(key: key, filename: "f", byte_size: 1, checksum: "x")
    end

    assert_equal [ "Gigs", "Map Images" ], MediaAssetFolders.list
  end
end
