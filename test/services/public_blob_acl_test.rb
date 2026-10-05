require "test_helper"
require "active_storage/service/s3_service"

class PublicBlobAclTest < ActiveSupport::TestCase
  setup do
    @blob = ActiveStorage::Blob.create_before_direct_upload!(
      key: "Gig Flyers/abc123", filename: "flyer.jpg", byte_size: 1, checksum: "x"
    )
  end

  test "no-ops on a service that is not public" do
    # The test environment stores on Disk, which has no bucket and no ACLs.
    assert_not PublicBlobAcl.apply(@blob)
  end

  test "grants public read on the blob's own key" do
    service = s3_service

    @blob.stub(:service, service) do
      assert PublicBlobAcl.apply(@blob)
    end

    request = service.bucket.client.api_requests.find { |r| r[:operation_name] == :put_object_acl }
    assert_equal "ig-mcp-images", request[:params][:bucket]
    assert_equal "Gig Flyers/abc123", request[:params][:key]
    assert_equal "public-read", request[:params][:acl]
  end

  test "returns false when Spaces rejects the grant" do
    service = s3_service(stub_responses: { put_object_acl: "AccessDenied" })

    @blob.stub(:service, service) do
      assert_not PublicBlobAcl.apply(@blob)
    end
  end

  private

  def s3_service(stub_responses: true)
    ActiveStorage::Service::S3Service.new(
      bucket: "ig-mcp-images", region: "sfo3", access_key_id: "k", secret_access_key: "s",
      public: true, stub_responses: stub_responses
    )
  end
end
