# frozen_string_literal: true

class KnownPerson < ApplicationRecord
  belongs_to :user
  has_one_attached :reference_image

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :reference_image_source_present

  def public_url
    if reference_image.attached?
      reference_image.url
    else
      reference_image_url.presence
    end
  end

  def public_url?
    public_url.present?
  end

  private

  def reference_image_source_present
    return if reference_image.attached? || reference_image_url.present?
    errors.add(:base, "Attach a photo or provide an image URL")
  end
end
