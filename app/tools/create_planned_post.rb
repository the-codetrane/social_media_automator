class CreatePlannedPost < RubyLLM::Tool
  description "Create a new planned social media post"

  param :user_id,
    type: :integer,
    desc: "The current user's ID"
  param :platform,
    type: :string,
    desc: "Target platform: instagram, youtube, or facebook"
  param :media_asset_id,
    type: :integer,
    desc: "ID of the media asset to use (obtain via resolve_media_asset if you have a URL)"
  param :caption,
    type: :string,
    desc: "Post caption text"
  param :hashtags,
    type: :string,
    desc: "Hashtag string to append, e.g. '#travel #photo #adventure'"
  param :status,
    type: :string,
    desc: "Post status: draft or scheduled",
    required: false
  param :scheduled_at,
    type: :string,
    desc: "ISO 8601 datetime for scheduling, e.g. 2026-04-21T10:00:00Z. Required when status is scheduled.",
    required: false
  param :social_template_id,
    type: :integer,
    desc: "Optional social template ID to associate with the post",
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
