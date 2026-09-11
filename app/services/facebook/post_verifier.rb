# frozen_string_literal: true

module Facebook
  # Fetches the current state of a published Facebook Page post.
  #
  # Usage:
  #   result = Facebook::PostVerifier.new(user).verify(external_post_id)
  #   result["permalink_url"]  # => "https://www.facebook.com/..."
  #
  #   result = Facebook::PostVerifier.new(user).verify_story(external_post_id)
  #   result["url"]            # => "https://www.facebook.com/stories/..."
  class PostVerifier
    FIELDS = "id,message,created_time,permalink_url"

    # A story is not readable as a post object — none of FIELDS applies to one —
    # so stories are found by listing the Page's stories and matching on post_id.
    STORIES_LIMIT = 100

    # Recorded as the status when a story is no longer in the Page's list. It is
    # not a value Meta returns: a story drops out after its 24 hours are up, or
    # once archived on a Page that has not enabled the story archive. Neither is
    # a publishing failure, so it is reported rather than raised.
    UNLISTED_STATUS = "UNLISTED"

    def initialize(user)
      @user    = user
      @page_id = Facebook::PageToken.page_id_for!(user)
    end

    # @param external_post_id [String] the Facebook post ID stored on PlannedPost
    # @return [Hash] parsed API response
    def verify(external_post_id)
      client.get(external_post_id, fields: FIELDS)
    end

    # The Page's story matching this post ID.
    #
    # GET /{page-id}/stories answers with one entry per story:
    #   { "post_id", "status", "creation_time", "media_type", "media_id", "url" }
    #
    # @param external_post_id [String] the story's post_id stored on PlannedPost
    # @return [Hash] the matching entry, or { "status" => UNLISTED_STATUS }
    def verify_story(external_post_id)
      response = client.get("#{@page_id}/stories", limit: STORIES_LIMIT)

      story = Array(response["data"]).find { |entry| entry["post_id"].to_s == external_post_id.to_s }

      story || { "status" => UNLISTED_STATUS }
    end

    private

    def client
      @client ||= Instagram::ApiClient.new(@user, access_token: fetch_page_access_token)
    end

    def fetch_page_access_token
      Facebook::PageToken.fetch(@user, @page_id)
    end
  end
end
