# frozen_string_literal: true

# Namespace module for all TikTok Content Posting API service classes.
# Zeitwerk requires this file to exist at app/services/tiktok.rb so it can
# correctly map the TikTok:: constant to the app/services/tiktok/ directory.
# (The "TikTok" acronym is registered in config/initializers/inflections.rb.)
#
# All error classes are defined here so they are available as soon as the
# TikTok namespace is loaded, without Zeitwerk needing separate files for
# each subclass.
module TikTok
  # Base error for all TikTok API failures.
  #
  # TikTok returns a JSON error object on every response — success is
  # signalled by error.code == "ok", not by the absence of the object.
  class Error < StandardError
    attr_reader :code, :log_id

    def initialize(message = nil, code: nil, log_id: nil)
      super(message)
      @code   = code
      @log_id = log_id
    end
  end

  # Raised for retryable TikTok API failures (5xx, unclassified error codes).
  class ApiError < Error; end

  # Raised when the per-token or per-day posting quota is exhausted.
  class RateLimitError < Error; end

  # Raised when the stored access token is invalid and could not be refreshed,
  # or when the app was not granted the scopes it needs.
  class TokenExpiredError < Error; end

  # Raised for failures that will never succeed on retry — unverified media
  # domains, privacy levels the creator cannot use, unaudited-client
  # restrictions, banned accounts and malformed requests.  These must stay
  # outside ApiError so the publish job does not burn retries on them.
  class PermanentError < Error; end

  # Raised when a chunked FILE_UPLOAD transfer fails mid-flight.
  class UploadError < Error; end

  # Raised when a publish stays in a non-terminal status for too long.
  class PublishTimeoutError < Error; end

  # Error codes that mean "try again later".
  RATE_LIMIT_CODES = %w[
    rate_limit_exceeded
    spam_risk_too_many_posts
  ].freeze

  # Error codes that mean the stored credentials are no longer usable.
  TOKEN_ERROR_CODES = %w[
    access_token_invalid
    scope_not_authorized
    invalid_grant
    invalid_request
  ].freeze

  # Error codes that will never succeed without a configuration change.
  PERMANENT_ERROR_CODES = %w[
    invalid_param
    url_ownership_unverified
    privacy_level_option_mismatch
    unaudited_client_can_only_post_to_private_accounts
    spam_risk_user_banned_from_posting
    reached_active_user_cap
  ].freeze

  # Map a TikTok error code string onto the error class the callers expect.
  #
  # @param code [String, nil]
  # @return [Class]
  def self.error_class_for(code)
    case code.to_s
    when *RATE_LIMIT_CODES      then RateLimitError
    when *TOKEN_ERROR_CODES     then TokenExpiredError
    when *PERMANENT_ERROR_CODES then PermanentError
    else                             ApiError
    end
  end
end
