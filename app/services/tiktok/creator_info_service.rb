# frozen_string_literal: true

module TikTok
  # Queries the creator's posting capabilities.
  #
  # TikTok requires this call before a direct post: the privacy_level submitted
  # to /post/publish/video/init/ must be one of the values it returns, and it
  # also reports the creator's maximum video duration and whether comments,
  # duets and stitches are switched off account-wide.
  #
  # Usage:
  #   info = TikTok::CreatorInfoService.new(user).query
  #   info["privacy_level_options"]        # => ["PUBLIC_TO_EVERYONE", "SELF_ONLY", ...]
  #   info["max_video_post_duration_sec"]  # => 600
  class CreatorInfoService
    ENDPOINT = "post/publish/creator_info/query/"

    def initialize(user)
      @client = TikTok::ApiClient.new(user)
    end

    # @return [Hash] the "data" object from the API response
    def query
      result = @client.post(ENDPOINT)
      result["data"] || {}
    end
  end
end
