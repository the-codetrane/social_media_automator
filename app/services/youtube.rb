# frozen_string_literal: true

# Namespace module for all YouTube Data API v3 service classes.
# Zeitwerk requires this file to exist at app/services/youtube.rb so it can
# correctly map the YouTube:: constant to the app/services/youtube/ directory.
module YouTube
  # Base error for all YouTube API failures.
  class Error < StandardError
    attr_reader :code, :reason

    def initialize(message = nil, code: nil, reason: nil)
      super(message)
      @code   = code
      @reason = reason
    end
  end

  # Raised when the YouTube Data API returns an error response.
  class ApiError < Error; end

  # Raised when the daily upload quota is exhausted.
  class RateLimitError < Error; end

  # Raised when the stored OAuth credentials have expired and refresh failed.
  class TokenExpiredError < Error; end

  # Raised when the video upload itself fails mid-transfer.
  class UploadError < Error; end
end
