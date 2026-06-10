# frozen_string_literal: true

require "exifr/jpeg"

class MediaAsset < ApplicationRecord
  enum :media_type, { image: 0, video: 1, audio: 2 }
  enum :status, { discovered: 0, processed: 1, failed: 2, archived: 3 }

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

  has_many :planned_posts, dependent: :destroy

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
