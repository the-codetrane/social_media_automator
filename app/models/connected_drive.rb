# frozen_string_literal: true

class ConnectedDrive < ApplicationRecord
  PROVIDERS = %w[google_drive].freeze

  belongs_to :user
  has_many :media_assets, dependent: :destroy

  validates :name, presence: true
  validates :folder_id, presence: true
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :sync_interval_minutes, presence: true,
                                    numericality: { only_integer: true, greater_than: 0 }
  validates :folder_id, uniqueness: { scope: :provider }

  scope :due_for_sync, -> {
    where("last_synced_at IS NULL OR last_synced_at <= ?",
          Time.current - minimum(:sync_interval_minutes).minutes)
  }

  def synced_recently?
    last_synced_at.present? && last_synced_at >= sync_interval_minutes.minutes.ago
  end

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end
end

