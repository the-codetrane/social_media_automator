class UpdatePlannedPost < RubyLLM::Tool
  description "Update an existing planned post. Can modify caption, hashtags, schedule, status, " \
              "or replace/reorder media assets to convert a single-photo post into a carousel. " \
              "Pass media_asset_ids (ordered array of existing asset IDs) to set or reorder carousel images; " \
              "the first ID becomes the primary asset. All fields except id are optional."

  param :id,
    type: :integer,
    desc: "The planned post ID to update"
  param :caption,
    type: :string,
    desc: "New caption text",
    required: false
  param :hashtags,
    type: :string,
    desc: "New hashtag string, e.g. '#blues #livemusic'",
    required: false
  param :status,
    type: :string,
    desc: "New status: draft or scheduled",
    required: false
  param :scheduled_at,
    type: :string,
    desc: "New scheduled time as ISO 8601, e.g. 2026-06-01T19:00:00Z. Required when changing status to scheduled.",
    required: false
  param :social_template_id,
    type: :integer,
    desc: "Social template ID to associate with the post",
    required: false
  param :media_asset_ids,
    type: :array,
    desc: "Ordered list of existing MediaAsset IDs. First ID becomes the primary asset. " \
          "Pass 2–10 IDs to create or reorder a carousel.",
    required: false

  def execute(id:, caption: nil, hashtags: nil, status: nil, scheduled_at: nil,
              social_template_id: nil, media_asset_ids: nil)
    post = PlannedPost.find_by(id: id)
    return { error: "Planned post ##{id} not found" } unless post

    attrs = {}
    attrs[:caption]            = caption            if caption.present?
    attrs[:hashtags]           = hashtags            if hashtags.present?
    attrs[:status]             = status              if status.present?
    attrs[:social_template_id] = social_template_id if social_template_id.present?
    attrs[:scheduled_at]       = Time.zone.parse(scheduled_at) if scheduled_at.present?

    if media_asset_ids.present?
      ids = Array(media_asset_ids).map(&:to_i).reject(&:zero?)
      return { error: "media_asset_ids must not be empty" } if ids.empty?

      existing = MediaAsset.where(id: ids).pluck(:id)
      missing = ids - existing
      return { error: "Media assets not found: #{missing.join(', ')}" } if missing.any?

      attrs[:media_asset_id] = ids.first
      payload = (post.platform_payload || {}).merge("carousel_asset_ids" => ids)
      attrs[:platform_payload] = payload
    end

    if post.update(attrs)
      carousel_ids = post.platform_payload&.dig("carousel_asset_ids")
      {
        id: post.id,
        platform: post.platform,
        status: post.status,
        media_asset_id: post.media_asset_id,
        carousel_asset_ids: carousel_ids || [ post.media_asset_id ],
        is_carousel: carousel_ids.present? && carousel_ids.size > 1,
        caption: post.caption,
        hashtags: post.hashtags,
        scheduled_at: post.scheduled_at&.iso8601,
        updated_at: post.updated_at.iso8601
      }
    else
      { errors: post.errors.full_messages }
    end
  end
end
