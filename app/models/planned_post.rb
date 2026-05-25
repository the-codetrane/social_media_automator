# frozen_string_literal: true

class PlannedPost < ApplicationRecord
  enum :platform, { instagram: 0, youtube: 1, facebook: 2 }
  enum :status, { draft: 0, scheduled: 1, published: 2, failed: 3, canceled: 4 }

  belongs_to :media_asset
  belongs_to :social_template, optional: true
  belongs_to :user

  validates :platform, presence: true
  validates :status, presence: true
  validates :scheduled_at, presence: true, if: :scheduled?
  validate :published_at_not_in_future, if: :published?
  validate :scheduled_at_in_future, if: :scheduled?

  scope :upcoming, -> { where(status: :scheduled).where("scheduled_at > ?", Time.current).order(:scheduled_at) }
  scope :for_platform, ->(platform) { where(platform: platform) }

  def post_type
    (platform_payload&.dig("carousel_asset_ids")&.size.to_i >= 2) ? "carousel" : "single"
  end

  private

  def published_at_not_in_future
    if published_at.present? && published_at > Time.current
      errors.add(:published_at, "cannot be in the future")
    end
  end

  def scheduled_at_in_future
    if scheduled_at.present? && scheduled_at <= Time.current
      errors.add(:scheduled_at, "must be in the future")
    end
  end
end
