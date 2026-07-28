class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  has_many :planned_posts, dependent: :destroy
  has_many :social_templates, dependent: :nullify
  has_many :known_people, dependent: :destroy

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
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

  # True if the stored token has already expired.
  def instagram_token_expired?
    instagram_connected? &&
      instagram_token_expires_at.present? &&
      instagram_token_expires_at <= Time.current
  end

  # True if the stored token is expired or will expire within +buffer+.
  def instagram_token_expiring?(buffer: 7.days)
    return true unless instagram_connected?
    return true if instagram_token_expires_at.blank?
    instagram_token_expires_at <= Time.current + buffer
  end

  # ------------------------------------------------------------------
  # TikTok credentials
  # Columns: tiktok_open_id, tiktok_access_token, tiktok_token_expires_at,
  #          tiktok_refresh_token, tiktok_refresh_expires_at,
  #          tiktok_username, tiktok_scope
  #
  # TikTok access tokens only live 24 hours, so the default expiry buffer is
  # minutes rather than the days used for Instagram — TikTok::ApiClient
  # refreshes them automatically before each request.
  # ------------------------------------------------------------------

  # True if a TikTok access token has been stored.
  def tiktok_connected?
    tiktok_access_token.present? && tiktok_open_id.present?
  end

  # True if the stored access token has already expired.
  def tiktok_token_expired?
    tiktok_connected? &&
      tiktok_token_expires_at.present? &&
      tiktok_token_expires_at <= Time.current
  end

  # True if the stored access token is expired or will expire within +buffer+.
  def tiktok_token_expiring?(buffer: 5.minutes)
    return true unless tiktok_connected?
    return true if tiktok_token_expires_at.blank?
    tiktok_token_expires_at <= Time.current + buffer
  end

  # True if the 365-day refresh token has expired — the user must reconnect.
  def tiktok_refresh_expired?
    tiktok_refresh_token.present? &&
      tiktok_refresh_expires_at.present? &&
      tiktok_refresh_expires_at <= Time.current
  end
end
