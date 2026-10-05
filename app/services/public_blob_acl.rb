# frozen_string_literal: true

# Grants public read on a blob that the browser direct-uploaded.
#
# ActiveStorage asks for the ACL by putting `x-amz-acl=public-read` in the query
# string of its presigned direct-upload URL (S3Service#url_for_direct_upload).
# Real S3 honours that; DigitalOcean Spaces silently ignores it and keeps the
# object private, because `headers_for_direct_upload` never sends the ACL as a
# header the browser could transmit. Instagram can only fetch media over a
# public URL, so the grant is re-applied here once the upload has landed.
#
# Server-side uploads are unaffected — S3Service#upload passes the ACL to
# `put_object` as a real header, which Spaces does honour.
module PublicBlobAcl
  module_function

  # @param blob [ActiveStorage::Blob]
  # @return [Boolean] true when the grant was applied
  def apply(blob)
    service = blob.service
    return false unless service.public? && service.respond_to?(:bucket)

    service.bucket.client.put_object_acl(
      bucket: service.bucket.name,
      key: blob.key,
      acl: "public-read"
    )
    true
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.warn("PublicBlobAcl: could not grant public read on #{blob.key}: #{e.message}")
    false
  end
end
