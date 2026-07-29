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

  # Raised when the credentials for the selected mode are missing.
  class ConfigurationError < Error; end

  # ------------------------------------------------------------------
  # Sandbox / production mode
  #
  # A TikTok app has a separate sandbox with its own client key and secret.
  # Both flows use the same endpoints — only the credential pair differs — so
  # switching modes is purely a matter of which pair we hand to the OAuth and
  # API calls.
  #
  # The mode is resolved in this order, first match wins:
  #   1. AppSetting "tiktok_mode"  — toggled from Admin > TikTok, no redeploy
  #   2. ENV["TIKTOK_MODE"]        — pin a whole deployment
  #   3. credentials tiktok:mode   — a committed default
  #   4. DEFAULT_MODE ("production")
  #
  # Tokens are NOT interchangeable between modes: one issued by the sandbox app
  # is meaningless to the production app. User#tiktok_environment records which
  # mode minted the stored token, and TikTok::ApiClient refuses to use a token
  # from the wrong one.
  # ------------------------------------------------------------------

  MODES        = %w[production sandbox].freeze
  DEFAULT_MODE = "production"
  MODE_SETTING = "tiktok_mode"

  # @return [String] "production" or "sandbox"
  def self.mode
    raw = stored_mode.presence ||
      ENV["TIKTOK_MODE"].presence ||
      Rails.application.credentials.dig(:tiktok, :mode).presence ||
      DEFAULT_MODE

    MODES.include?(raw.to_s) ? raw.to_s : DEFAULT_MODE
  end

  def self.sandbox?
    mode == "sandbox"
  end

  # Persist the active mode.  Returns the mode that was set.
  #
  # @param new_mode [String]
  # @raise [ArgumentError] for anything outside MODES
  def self.mode=(new_mode)
    unless MODES.include?(new_mode.to_s)
      raise ArgumentError, "Unknown TikTok mode #{new_mode.inspect} (expected one of #{MODES.join(', ')})"
    end

    AppSetting.set(MODE_SETTING, new_mode.to_s)
    new_mode.to_s
  end

  # @return [String] the client key for the active (or given) mode
  def self.client_key(for_mode: mode)
    credentials_for(for_mode)[:client_key].presence ||
      raise(ConfigurationError, missing_credentials_message(for_mode, "client_key"))
  end

  # @return [String] the client secret for the active (or given) mode
  def self.client_secret(for_mode: mode)
    credentials_for(for_mode)[:client_secret].presence ||
      raise(ConfigurationError, missing_credentials_message(for_mode, "client_secret"))
  end

  # True when both halves of the credential pair are present for a mode.
  def self.configured?(for_mode: mode)
    creds = credentials_for(for_mode)
    creds[:client_key].present? && creds[:client_secret].present?
  end

  # Resolve a mode's credential pair.
  #
  # Three layouts are accepted so this works whichever way the keys were added:
  #
  #   tiktok:                     tiktok:                      tiktok:
  #     production:                 client_key: ...              client_key: ...
  #       client_key: ...           client_secret: ...           client_secret: ...
  #       client_secret: ...        sandbox_client_key: ...
  #     sandbox:                    sandbox_client_secret: ...
  #       client_key: ...
  #       client_secret: ...
  #
  # The flat `client_key` / `client_secret` pair is treated as production, so an
  # existing configuration keeps working untouched.
  #
  # @return [Hash] { client_key:, client_secret: }
  def self.credentials_for(for_mode)
    tiktok = Rails.application.credentials.tiktok || {}
    nested = tiktok[for_mode.to_sym]

    if nested.is_a?(Hash)
      return { client_key: nested[:client_key], client_secret: nested[:client_secret] }
    end

    if for_mode.to_s == "sandbox"
      { client_key:    tiktok[:sandbox_client_key],
        client_secret: tiktok[:sandbox_client_secret] }
    else
      { client_key:    tiktok[:client_key].presence    || tiktok[:production_client_key],
        client_secret: tiktok[:client_secret].presence || tiktok[:production_client_secret] }
    end
  end

  # AppSetting lives in the database, which is not guaranteed to be reachable
  # (asset precompile, a boot before migrations have run), so never let a
  # lookup failure take down credential resolution.
  def self.stored_mode
    AppSetting.get(MODE_SETTING)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.debug("[TikTok] Could not read #{MODE_SETTING} from AppSetting: #{e.message}")
    nil
  end
  private_class_method :stored_mode

  def self.missing_credentials_message(for_mode, field)
    "No TikTok #{field} configured for #{for_mode} mode. " \
    "Add it with bin/rails credentials:edit under tiktok:#{for_mode}:#{field} " \
    "(or tiktok:#{field} for production)."
  end
  private_class_method :missing_credentials_message

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
