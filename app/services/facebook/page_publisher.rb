# frozen_string_literal: true

module Facebook
  # Publishes a PlannedPost to a Facebook Page feed via the Meta Pages API.
  #
  # Requires the user to have completed Instagram OAuth with pages_manage_posts
  # permission and have instagram_page_id set.
  #
  # Usage:
  #   publisher = Facebook::PagePublisher.new(user)
  #   publisher.publish(planned_post)
  class PagePublisher
    # @param user [User] must have instagram_page_id + instagram_access_token set
    def initialize(user)
      @user    = user
      @page_id = user.instagram_page_id.presence ||
        raise(Instagram::ApiError, "User #{user.id} has no Facebook page_id set")
    end

    # @param planned_post [PlannedPost]
    # @return [String] the Facebook post ID
    def publish(planned_post)
      page_token = fetch_page_access_token
      post_id    = post_content(planned_post, page_token)

      planned_post.update!(
        status:           :published,
        external_post_id: post_id,
        published_at:     Time.current
      )

      post_id
    end

    private

    # Exchange the stored user token for a Page access token.
    def fetch_page_access_token
      result = Instagram::ApiClient.new(@user).get(@page_id, fields: "access_token")
      token  = result["access_token"]
      raise Instagram::ApiError, "Could not retrieve Page access token for page #{@page_id}" if token.blank?
      token
    end

    def post_content(planned_post, page_token)
      client  = Instagram::ApiClient.new(@user, access_token: page_token)
      asset   = planned_post.media_asset
      caption = build_caption(planned_post)

      if asset&.video?
        result = client.post("#{@page_id}/videos", file_url: asset.public_url, description: caption)
        result["id"]
      elsif asset&.image?
        result = client.post("#{@page_id}/photos", url: asset.public_url, message: caption)
        result["post_id"] || result["id"]
      else
        result = client.post("#{@page_id}/feed", message: caption)
        result["id"]
      end
    end

    def build_caption(planned_post)
      [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?).join("\n\n")
    end
  end
end
