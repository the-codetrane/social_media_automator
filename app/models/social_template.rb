# frozen_string_literal: true

class SocialTemplate < ApplicationRecord
  enum :platform, { instagram: 0, youtube: 1, facebook: 2, tiktok: 3 }

  belongs_to :user, optional: true
  has_many :planned_posts, dependent: :nullify

  validates :name, presence: true
  validates :platform, presence: true
  validates :name, uniqueness: { scope: :platform }
  validates :max_caption_length,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true

  scope :for_platform, ->(platform) { where(platform: platform) }
  scope :global, -> { where(user_id: nil) }
end
