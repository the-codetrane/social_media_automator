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
  has_one_attached :static_map_image

  before_validation :extract_gps_from_exif,
    if: -> { file.attached? && image? && latitude.nil? && mime_type&.include?("jpeg") }

  # Restrict rather than cascade: posts are history, and archiving
  # (soft delete) is the supported way to retire an asset.
  has_many :planned_posts, dependent: :restrict_with_error

  validates :external_id, presence: true, uniqueness: true
  validates :media_type, presence: true
  validates :status, presence: true
  validates :first_seen_at, presence: true
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :file_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :width, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_commit :enqueue_static_map_fetch,
    if: -> { geocoded? && (saved_change_to_latitude? || saved_change_to_longitude?) }

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

  private

  def enqueue_static_map_fetch
    FetchStaticMapJob.perform_later(id) unless static_map_image.attached?
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
