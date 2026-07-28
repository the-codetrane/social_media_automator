# frozen_string_literal: true

# Public, unauthenticated static pages.
#
# The Terms of Service and Privacy Policy have to be reachable without signing
# in: Meta, Google and TikTok all fetch these URLs during app review, and a
# redirect to the sign-in page reads as a broken link to their reviewers.
class PagesController < ApplicationController
  allow_unauthenticated_access only: [ :tos, :privacy ]

  # Bump this whenever the wording of either document changes.
  LAST_UPDATED  = Date.new(2026, 7, 28)
  CONTACT_EMAIL = "michael.cain@2100enterprises.com"
  OPERATOR      = "Cain & Co."
  SERVICE_NAME  = "Social Media Automator"

  before_action :set_document_metadata, only: [ :tos, :privacy ]

  def tos
  end

  def privacy
  end

  private

  def set_document_metadata
    @last_updated  = LAST_UPDATED
    @contact_email = CONTACT_EMAIL
    @operator      = OPERATOR
    @service_name  = SERVICE_NAME
  end
end
