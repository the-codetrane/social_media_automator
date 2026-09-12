# frozen_string_literal: true

# Folders ("directories") that uploaded media can be filed under. Files in
# DigitalOcean Spaces are organised by key prefix — "Map Images/…",
# "Images From Chat/…" — so a folder is simply the part of a blob key before
# the last slash.
#
# On S3-compatible services the list comes straight from the bucket, so
# folders created outside the app show up too. Elsewhere (Disk in dev/test)
# it is derived from the keys of blobs already in the database.
module MediaAssetFolders
  # Anything that would escape the folder or produce an odd key.
  INVALID_SEGMENT = /\A\.{1,2}\z/

  module_function

  # @return [Array<String>] folder names without a trailing slash, sorted
  def list
    service = ActiveStorage::Blob.service

    folders =
      if service.respond_to?(:client) && service.respond_to?(:bucket)
        list_from_bucket(service)
      else
        list_from_blobs
      end

    folders.map { |name| name.delete_suffix("/") }.reject(&:blank?).uniq.sort
  end

  # Normalises a user-supplied folder name into a key prefix. Returns nil when
  # the name is blank or contains a segment that would escape the folder.
  #
  # @param name [String, nil]
  # @return [String, nil] e.g. "Gigs/2026" (no leading or trailing slash)
  def sanitize(name)
    segments = name.to_s.strip.split("/").map(&:strip).reject(&:blank?)
    return nil if segments.empty?
    return nil if segments.any? { |segment| segment.match?(INVALID_SEGMENT) }

    segments.join("/")
  end

  # Builds a unique blob key inside the given folder.
  #
  # @param folder [String] already sanitized
  # @return [String]
  def key_for(folder)
    "#{folder}/#{ActiveStorage::Blob.generate_unique_secure_token}"
  end

  def list_from_bucket(service)
    response = service.bucket.client.list_objects_v2(bucket: service.bucket.name, delimiter: "/")
    response.common_prefixes.map(&:prefix)
  end

  def list_from_blobs
    ActiveStorage::Blob.where("key LIKE ?", "%/%").distinct.pluck(:key).map do |key|
      key.rpartition("/").first
    end
  end
end
