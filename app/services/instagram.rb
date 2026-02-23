# frozen_string_literal: true

# Namespace module for all Meta / Instagram API service classes.
# Zeitwerk requires this file to exist at app/services/instagram.rb so it can
# correctly map the Instagram:: constant to the app/services/instagram/ directory.
#
# All error classes are defined here so they are available as soon as the
# Instagram namespace is loaded, without Zeitwerk needing separate files for
# each subclass.
module Instagram
  # Base error for all Instagram API failures.
  class Error < StandardError
    attr_reader :code, :type, :fbtrace_id

    def initialize(message = nil, code: nil, type: nil, fbtrace_id: nil)
      super(message)
      @code        = code
      @type        = type
      @fbtrace_id  = fbtrace_id
    end
  end

  # Raised when the Meta API returns an error response.
  class ApiError < Error; end

  # Raised when the 25 posts/24 h publishing quota is exhausted.
  class RateLimitError < Error; end

  # Raised when a media container stays in a non-FINISHED state too long.
  class ContainerTimeoutError < Error; end

  # Raised when the stored access token has expired and refresh failed.
  class TokenExpiredError < Error; end
end
