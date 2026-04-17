# frozen_string_literal: true

module Instagram
  # Fetches the current state of a published Instagram post from the Graph API.
  #
  # Usage:
  #   result = Instagram::PostVerifier.new(user).verify(external_post_id)
  #   result["permalink"]  # => "https://www.instagram.com/p/..."
  class PostVerifier
    FIELDS = "id,permalink,timestamp,media_type,like_count,comments_count"

    def initialize(user)
      @client = Instagram::ApiClient.new(user)
    end

    # @param external_post_id [String] the ig_media_id stored on PlannedPost
    # @return [Hash] parsed API response
    def verify(external_post_id)
      @client.get(external_post_id, fields: FIELDS)
    end
  end
end
