# frozen_string_literal: true

# Namespace module for all Google Drive API service classes.
# Zeitwerk requires this file to exist at app/services/google_drive.rb so it
# can correctly map the GoogleDrive:: constant to the
# app/services/google_drive/ directory.
#
# All shared error classes are defined here so they are available as soon as
# the GoogleDrive namespace is loaded, without Zeitwerk needing separate files
# for each subclass.
module GoogleDrive
  # Base error for all Google Drive API failures.
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end
  end

  # Raised when the Drive API returns a non-2xx, non-401 error response.
  class ApiError < Error; end

  # Raised when the stored access token is expired or revoked and the
  # automatic refresh attempt also failed.
  class TokenExpiredError < Error; end

  # Raised when a token refresh attempt fails (e.g. the refresh token has
  # been revoked or no refresh token is stored).
  class TokenRefreshError < Error; end
end
