class ListPlannedPosts < RubyLLM::Tool
  description "List planned social media posts, optionally filtered by status, platform, or user. " \
              "Use this to find single-photo posts that need to be converted to carousels, " \
              "or to review what is currently scheduled."

  param :status,
    type: :string,
    desc: "Filter by status: draft, scheduled, published, failed, or canceled",
    required: false
  param :platform,
    type: :string,
    desc: "Filter by platform: instagram, youtube, facebook, or tiktok",
    required: false
  param :user_id,
    type: :integer,
    desc: "Filter by user ID",
    required: false

  def execute(status: nil, platform: nil, user_id: nil)
    posts = PlannedPost.all
    posts = posts.where(status: status) if status.present?
    posts = posts.where(platform: platform) if platform.present?
    posts = posts.where(user_id: user_id) if user_id.present?
    posts = posts.order(:scheduled_at)

    posts.map { |p| serialize(p) }
  end

  private

  def serialize(post)
    carousel_ids = post.platform_payload&.dig("carousel_asset_ids")
    {
      id: post.id,
      user_id: post.user_id,
      platform: post.platform,
      status: post.status,
      media_asset_id: post.media_asset_id,
      carousel_asset_ids: carousel_ids || [ post.media_asset_id ],
      is_carousel: carousel_ids.present? && carousel_ids.size > 1,
      caption: post.caption,
      hashtags: post.hashtags,
      scheduled_at: post.scheduled_at&.iso8601
    }
  end
end
