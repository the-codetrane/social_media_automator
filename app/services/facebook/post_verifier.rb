# frozen_string_literal: true

module Facebook
  # Fetches the current state of a published Facebook Page post.
  #
  # Usage:
  #   result = Facebook::PostVerifier.new(user).verify(external_post_id)
  #   result["permalink_url"]  # => "https://www.facebook.com/..."
  class PostVerifier
    FIELDS = "id,message,created_time,permalink_url"

    def initialize(user)
      @user    = user
      @page_id = user.instagram_page_id.presence ||
        raise(Instagram::ApiError, "User #{user.id} has no Facebook page_id set")
    end

    # @param external_post_id [String] the Facebook post ID stored on PlannedPost
    # @return [Hash] parsed API response
    def verify(external_post_id)
      page_token = fetch_page_access_token
      Instagram::ApiClient.new(@user, access_token: page_token).get(external_post_id, fields: FIELDS)
    end

    private

    def fetch_page_access_token
      result = Instagram::ApiClient.new(@user).get(@page_id, fields: "access_token")
      token  = result["access_token"]
      raise Instagram::ApiError, "Could not retrieve Page access token for page #{@page_id}" if token.blank?
      token
    end
  end
end
