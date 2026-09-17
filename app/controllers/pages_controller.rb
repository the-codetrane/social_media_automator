# frozen_string_literal: true

# Public, unauthenticated static pages.
#
# The home page, Terms of Service and Privacy Policy all have to be reachable
# without signing in: Meta, Google and TikTok fetch these URLs during app
# review. A redirect to the sign-in page reads as a broken link to their
# reviewers, and a site whose root *is* the sign-in page gets rejected as
# "a landing or login page" rather than a fully developed website.
class PagesController < ApplicationController
  allow_unauthenticated_access only: [ :home, :tos, :privacy ]

  # Bump this whenever the wording of either document changes.
  LAST_UPDATED  = Date.new(2026, 7, 28)
  CONTACT_EMAIL = "michael.cain@2100enterprises.com"
  OPERATOR      = "Cain & Co."
  SERVICE_NAME  = "Social Media Automator"

  before_action :set_document_metadata, only: [ :tos, :privacy ]

  # Signed-in users never need the marketing copy; send them to the dashboard
  # that used to live at the root URL. Sign-in and sign-up both redirect here
  # with a flash notice, so keep it alive across the extra hop.
  def home
    return unless authenticated?

    flash.keep
    redirect_to users_path
  end

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
