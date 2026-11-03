# frozen_string_literal: true

require "exifr/jpeg"

class MediaAsset < ApplicationRecord
  enum :media_type, { image: 0, video: 1, audio: 2 }
  # Processing pipeline state only. Archiving and publication are tracked
  # separately (archived_at / published_at) because an asset can be processed,
  # published and archived all at once. Value 3 was the old "archived" status —
  # migrated to archived_at; do not reuse it.
  enum :status, { discovered: 0, processed: 1, failed: 2 }

  # How an asset stands for reuse in a new post, most restrictive first.
  AVAILABILITIES = %w[archived published reserved available].freeze

  reverse_geocoded_by :latitude, :longitude do |obj, results|
    if (geo = results.first)
      obj.address = geo.address
      obj.city    = geo.city
      obj.state   = geo.state
      obj.country = geo.country
    end
  end
  after_validation :reverse_geocode, if: -> { (latitude_changed? || longitude_changed?) && latitude.present? }

  # ActiveStorage attachment for the media file (stored on DigitalOcean Spaces)
  has_one_attached :file

  before_validation :extract_gps_from_exif,
    if: -> { file.attached? && image? && latitude.nil? && mime_type&.include?("jpeg") }

  # Restrict rather than cascade: posts are history, and archiving
  # (soft delete) is the supported way to retire an asset.
  has_many :planned_posts, dependent: :restrict_with_error

  before_validation :assign_storage_key

  validates :external_id, presence: true, uniqueness: true
  validates :storage_key, uniqueness: true, allow_nil: true
  validates :media_type, presence: true
  validates :status, presence: true
  validates :first_seen_at, presence: true
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :file_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :width, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :images, -> { where(media_type: :image) }
  scope :videos, -> { where(media_type: :video) }
  scope :audios, -> { where(media_type: :audio) }
  scope :ready, -> { where(status: :processed) }

  scope :active,      -> { where(archived_at: nil) }
  scope :archived,    -> { where.not(archived_at: nil) }
  scope :published,   -> { where.not(published_at: nil) }
  scope :unpublished, -> { where(published_at: nil) }

  # Assets on a scheduled (not yet published) post, as the primary asset or a
  # carousel member. Computed from posts at query time rather than stored, so
  # it can never go stale.
  scope :reserved, ->(excluding: nil) {
    posts = reserving_posts(excluding: excluding)
    where(id: posts.select(:media_asset_id)).or(where(id: PlannedPost.carousel_media_asset_ids(posts)))
  }
  scope :unreserved, ->(excluding: nil) {
    posts = reserving_posts(excluding: excluding)
    where.not(id: posts.select(:media_asset_id)).where.not(id: PlannedPost.carousel_media_asset_ids(posts))
  }

  # Free to use in a new post: not archived, never published, not already on
  # another scheduled post.
  scope :available, ->(excluding: nil) { active.unpublished.unreserved(excluding: excluding) }

  # Narrow a relation to one AVAILABILITIES bucket; "all" or blank is a no-op.
  scope :with_availability, ->(availability, excluding: nil) {
    case availability.to_s
    when "available" then available(excluding: excluding)
    when "reserved"  then active.unpublished.reserved(excluding: excluding)
    when "published" then active.published
    when "archived"  then archived
    else all
    end
  }

  # IDs of assets on scheduled posts, as a Set for per-row lookups in lists.
  #
  # @param excluding [PlannedPost, nil] ignore this post — the one being
  #   edited should not count as reserving its own assets
  # @return [Set<Integer>]
  def self.reserved_ids(excluding: nil)
    posts = reserving_posts(excluding: excluding)
    (posts.pluck(:media_asset_id) + PlannedPost.carousel_media_asset_ids(posts).pluck(Arel.sql("CAST(carousel_ids.value AS INTEGER)")))
      .compact.to_set
  end

  # Posts whose assets count as reserved.
  def self.reserving_posts(excluding: nil)
    posts = PlannedPost.scheduled
    posts = posts.where.not(id: excluding.id) if excluding&.persisted?
    posts
  end

  def archived?
    archived_at.present?
  end

  def published?
    published_at.present?
  end

  def archive!
    update!(archived_at: Time.current) unless archived?
  end

  def unarchive!
    update!(archived_at: nil) if archived?
  end

  # Where this asset stands for reuse — one of AVAILABILITIES.
  #
  # @param reserved_ids [Set<Integer>, nil] precomputed MediaAsset.reserved_ids,
  #   to avoid a query per asset when rendering a list
  # @param excluding [PlannedPost, nil] see MediaAsset.reserved_ids
  def availability(reserved_ids: nil, excluding: nil)
    return "archived"  if archived?
    return "published" if published?

    reserved_ids ||= self.class.reserved_ids(excluding: excluding)
    reserved_ids.include?(id) ? "reserved" : "available"
  end

  # Every post this asset appears in, as the primary asset or a carousel member.
  def posts_using
    PlannedPost.using_media_asset(id)
  end

  def display_name
    CGI.unescape(external_name.presence || external_id.to_s)
  end

  # Returns the public URL for this media asset.
  # Prefers the ActiveStorage attachment URL, falls back to raw_metadata["public_url"]
  # for legacy records or externally-hosted media.
  #
  # @return [String, nil] the publicly accessible HTTPS URL
  def public_url
    if file.attached?
      # For DigitalOcean Spaces with public: true, use the direct URL
      file.url
    else
      # Fallback to legacy raw_metadata storage
      metadata = raw_metadata
      metadata = JSON.parse(metadata) if metadata.is_a?(String)
      metadata&.dig("public_url")
    end
  end

  # Check if the asset has a valid public URL available.
  #
  # @return [Boolean]
  def public_url?
    public_url.present?
  end

  # The Spaces object key a URL points at, or nil when the URL is not in our
  # bucket. Accepts the CDN host, the virtual-hosted origin and path-style
  # URLs, raw or percent-encoded, so every spelling of one object maps to the
  # same key. This key, not the URL string, is what identifies an asset.
  #
  # @param url [String, nil]
  # @return [String, nil]
  def self.storage_key_for_url(url)
    uri = URI.parse(url.to_s.strip.gsub(" ", "%20"))
    return nil unless uri.is_a?(URI::HTTP) && uri.host

    bucket = spaces_bucket
    host = uri.host.downcase
    path = uri.path.to_s
    return nil unless host.end_with?(".digitaloceanspaces.com")

    key =
      if host.start_with?("#{bucket}.")
        path.delete_prefix("/")
      elsif path.start_with?("/#{bucket}/")
        path.delete_prefix("/#{bucket}/")
      end
    key.present? ? URI.decode_uri_component(key) : nil
  rescue URI::InvalidURIError
    nil
  end

  # The Spaces key recorded in an asset's raw_metadata: the explicit "key"
  # when an importer stored one, otherwise derived from "public_url".
  #
  # @param metadata [Hash, String, nil] raw_metadata, possibly JSON-encoded
  # @return [String, nil]
  def self.storage_key_from_metadata(metadata)
    2.times { metadata = (JSON.parse(metadata) rescue nil) if metadata.is_a?(String) }
    return nil unless metadata.is_a?(Hash)

    metadata["key"].presence || storage_key_for_url(metadata["public_url"])
  end

  def self.spaces_bucket
    Rails.application.credentials.dig(:digitalocean, :spaces_bucket) || "ig-mcp-images"
  end

  private

  def assign_storage_key
    self.storage_key ||= file.attached? ? file.blob.key : self.class.storage_key_from_metadata(raw_metadata)
  end

  def extract_gps_from_exif
    file.open do |tempfile|
      exif = EXIFR::JPEG.new(tempfile.path)
      return unless exif&.gps
      self.latitude  = exif.gps.latitude
      self.longitude = exif.gps.longitude
    end
  rescue EXIFR::MalformedJPEG, EXIFR::MalformedTIFF
    # File lacks EXIF or GPS data — skip silently
  end
end
