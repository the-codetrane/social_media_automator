class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  has_many :connected_drives, dependent: :destroy
  has_many :planned_posts, dependent: :destroy
  has_many :social_templates, dependent: :nullify

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # ------------------------------------------------------------------
  # Instagram / Meta credentials
  # Columns: instagram_user_id, instagram_access_token,
  #          instagram_token_expires_at, instagram_page_id
  # ------------------------------------------------------------------

  # True if an Instagram access token has been stored.
  def instagram_connected?
    instagram_access_token.present? && instagram_user_id.present?
  end

  # True if the stored token is expired or will expire within +buffer+.
  def instagram_token_expiring?(buffer: 7.days)
    return true unless instagram_connected?
    return true if instagram_token_expires_at.blank?
    instagram_token_expires_at <= Time.current + buffer
  end
end
