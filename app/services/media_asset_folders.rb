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

  # Path separators, control characters and anything that would need escaping in
  # a public URL. Spaces, ampersands and parentheses are deliberately kept —
  # folders and objects already in the bucket use them.
  UNSAFE_FILENAME = %r{[/\\\x00-\x1f\x7f"<>\#?%{}|^~\[\]`]+}

  # How many suffixed names to try before giving up and using an opaque token.
  SUFFIX_ATTEMPTS = 5

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

  # Builds a blob key inside the given folder, named after the file the user
  # uploaded so the object is recognisable in Spaces instead of an opaque token.
  # A short random suffix is appended only when the name is already taken, so an
  # upload never overwrites an object that is already there.
  #
  # @param folder [String] already sanitized
  # @param filename [String, nil] as supplied by the browser
  # @return [String]
  def key_for(folder, filename: nil)
    name = sanitize_filename(filename)
    key  = "#{folder}/#{name}"
    return key unless key_taken?(key)

    extension = File.extname(name)
    stem      = name.delete_suffix(extension)

    SUFFIX_ATTEMPTS.times do
      key = "#{folder}/#{stem}-#{SecureRandom.hex(3)}#{extension}"
      return key unless key_taken?(key)
    end

    "#{folder}/#{ActiveStorage::Blob.generate_unique_secure_token}#{extension}"
  end

  # Reduces a browser-supplied filename to a single safe key segment. Returns an
  # opaque token when nothing usable is left, which also disposes of "." and
  # ".." before they can escape the folder.
  def sanitize_filename(filename)
    name = File.basename(filename.to_s.tr("\\", "/"))
             .gsub(UNSAFE_FILENAME, "-")
             .squeeze("-")
             .sub(/\A[-.[:space:]]+/, "")
             .sub(/[-[:space:]]+\z/, "")

    name.presence || ActiveStorage::Blob.generate_unique_secure_token
  end

  # Objects uploaded outside the app have no blob row, so the bucket is checked
  # too rather than trusting the database alone.
  def key_taken?(key)
    return true if ActiveStorage::Blob.exists?(key: key)

    ActiveStorage::Blob.service.exist?(key)
  rescue Aws::S3::Errors::ServiceError
    false
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
