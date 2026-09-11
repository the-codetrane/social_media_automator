# frozen_string_literal: true

module Facebook
  # Exchanges a User's stored Meta user token for a Page access token.
  #
  # Every Page-level write — feed posts, stories, verification — needs one, so
  # the lookup lives here rather than being copied into each service.
  #
  #   token  = Facebook::PageToken.fetch(user, page_id)
  #   client = Instagram::ApiClient.new(user, access_token: token)
  module PageToken
    module_function

    # @param user [User] must have instagram_access_token present
    # @param page_id [String]
    # @return [String] the Page access token
    # @raise [Instagram::ApiError] when the Page returns no token
    def fetch(user, page_id)
      result = Instagram::ApiClient.new(user).get(page_id, fields: "access_token")
      token  = result["access_token"]

      raise Instagram::ApiError, "Could not retrieve Page access token for page #{page_id}" if token.blank?

      token
    end

    # The Page ID a User publishes to, or raise if the account is not connected.
    #
    # @param user [User]
    # @return [String]
    def page_id_for!(user)
      user.instagram_page_id.presence ||
        raise(Instagram::ApiError, "User #{user.id} has no Facebook page_id set")
    end
  end
end
