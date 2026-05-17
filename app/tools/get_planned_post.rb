class GetPlannedPost < RubyLLM::Tool
  description "Fetch full details of a specific planned post by ID, including all media assets, " \
              "caption, hashtags, platform, scheduled time, and status."

  param :id,
    type: :integer,
    desc: "The planned post ID"

  def execute(id:)
    post = PlannedPost.find_by(id: id)
    return { error: "Planned post ##{id} not found" } unless post

    carousel_ids = post.platform_payload&.dig("carousel_asset_ids")
    {
      id: post.id,
      user_id: post.user_id,
      platform: post.platform,
      status: post.status,
      media_asset_id: post.media_asset_id,
      carousel_asset_ids: carousel_ids || [ post.media_asset_id ],
      is_carousel: carousel_ids.present? && carousel_ids.size > 1,
      social_template_id: post.social_template_id,
      caption: post.caption,
      hashtags: post.hashtags,
      scheduled_at: post.scheduled_at&.iso8601,
      published_at: post.published_at&.iso8601,
      platform_payload: post.platform_payload,
      created_at: post.created_at.iso8601,
      updated_at: post.updated_at.iso8601
    }
  end
end
