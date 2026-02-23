# frozen_string_literal: true

class MediaAsset < ApplicationRecord
  belongs_to :connected_drive

  enum :media_type, { image: 0, video: 1 }
  enum :status, { discovered: 0, processed: 1, failed: 2, archived: 3 }

  has_many :planned_posts, dependent: :destroy

  validates :external_id, presence: true, uniqueness: true
  validates :media_type, presence: true
  validates :status, presence: true
  validates :first_seen_at, presence: true
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validates :file_size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :width, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :images, -> { where(media_type: :image) }
  scope :videos, -> { where(media_type: :video) }
  scope :ready, -> { where(status: :processed) }
end


