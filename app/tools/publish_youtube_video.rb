class PublishYouTubeVideo < RubyLLM::Tool
  description "Publish a video to YouTube. Videos under 60 seconds are automatically " \
              "published as YouTube Shorts (#Shorts appended to title and description). " \
              "The first line of caption becomes the video title; full caption is used as description."

  parameter :user_id,
    type: :integer,
    description: "The current user's ID"
  parameter :media_asset_id,
    type: :integer,
    description: "ID of the video MediaAsset to upload (must be media_type: video with a public URL)"
  parameter :caption,
    type: :string,
    description: "Video caption. First line is used as the YouTube title (max 100 chars); full text is the description."
  parameter :hashtags,
    type: :string,
    description: "Hashtag string appended to the description, e.g. '#vlog #travel'",
    required: false
  parameter :privacy_status,
    type: :string,
    description: "Video visibility: public, unlisted, or private. Defaults to public.",
    required: false
  parameter :category_id,
    type: :string,
    description: "YouTube category ID, e.g. '22' (People & Blogs), '17' (Sports), '10' (Music). Defaults to '22'.",
    required: false
  parameter :tags,
    type: :string,
    description: "Comma-separated keyword tags for the video, e.g. 'travel,vlog,adventure'",
    required: false

  def execute(user_id:, media_asset_id:, caption:, hashtags: nil, privacy_status: nil, category_id: nil, tags: nil)
    user = User.find_by(id: user_id)
    return { error: "User #{user_id} not found" } unless user

    asset = MediaAsset.find_by(id: media_asset_id)
    return { error: "MediaAsset #{media_asset_id} not found" } unless asset
    return { error: "MediaAsset #{media_asset_id} is not a video" } unless asset.video?
    return { error: "MediaAsset #{media_asset_id} has no public URL" } unless asset.public_url?

    payload = {}
    payload["privacy_status"] = privacy_status                              if privacy_status.present?
    payload["category_id"]    = category_id                                 if category_id.present?
    payload["tags"]           = tags.split(",").map(&:strip).reject(&:blank?) if tags.present?

    planned_post = PlannedPost.create!(
      user:             user,
      platform:         :youtube,
      media_asset:      asset,
      caption:          caption,
      hashtags:         hashtags.to_s,
      status:           :scheduled,
      scheduled_at:     Time.current,
      platform_payload: payload
    )

    PublishYouTubePostJob.perform_later(planned_post.id)

    short = asset.duration_seconds.present? && asset.duration_seconds < 60
    {
      planned_post_id: planned_post.id,
      platform:        "youtube",
      video_type:      short ? "Short" : "video",
      status:          "publishing",
      caption:         caption,
      privacy_status:  payload.fetch("privacy_status", "public")
    }
  rescue => e
    { error: e.message }
  end
end
