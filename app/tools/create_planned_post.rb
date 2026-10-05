class CreatePlannedPost < RubyLLM::Tool
  description "Create a new planned social media post"

  parameter :user_id,
    type: :integer,
    description: "The current user's ID"
  parameter :platform,
    type: :string,
    description: "Target platform: instagram, youtube, facebook, or tiktok"
  parameter :media_asset_id,
    type: :integer,
    description: "ID of the media asset to use (obtain via resolve_media_asset if you have a URL)"
  parameter :caption,
    type: :string,
    description: "Post caption text"
  parameter :hashtags,
    type: :string,
    description: "Hashtag string to append, e.g. '#travel #photo #adventure'"
  parameter :status,
    type: :string,
    description: "Post status: draft or scheduled",
    required: false
  parameter :scheduled_at,
    type: :string,
    description: "ISO 8601 datetime for scheduling, e.g. 2026-04-21T10:00:00Z. Required when status is scheduled.",
    required: false
  parameter :social_template_id,
    type: :integer,
    description: "Optional social template ID to associate with the post",
    required: false

  def execute(user_id:, platform:, media_asset_id:, caption:, hashtags:, status: "draft", scheduled_at: nil, social_template_id: nil)
    post = PlannedPost.new(
      user_id: user_id,
      platform: platform,
      media_asset_id: media_asset_id,
      caption: caption,
      hashtags: hashtags,
      status: status,
      social_template_id: social_template_id
    )
    post.scheduled_at = Time.zone.parse(scheduled_at) if scheduled_at.present?

    if post.save
      { id: post.id, platform: post.platform, status: post.status, caption: post.caption, scheduled_at: post.scheduled_at }
    else
      { errors: post.errors.full_messages }
    end
  end
end
