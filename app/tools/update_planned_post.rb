class UpdatePlannedPost < RubyLLM::Tool
  description "Update an existing planned post. Can modify caption, hashtags, schedule, status, " \
              "or replace/reorder media assets to convert a single-photo post into a carousel. " \
              "Pass media_asset_ids (ordered array of existing asset IDs) to set or reorder carousel images; " \
              "the first ID becomes the primary asset. Pass collaborators to set Instagram collaborator tags. " \
              "All fields except id are optional."

  parameter :id,
    type: :integer,
    description: "The planned post ID to update"
  parameter :caption,
    type: :string,
    description: "New caption text",
    required: false
  parameter :hashtags,
    type: :string,
    description: "New hashtag string, e.g. '#blues #livemusic'",
    required: false
  parameter :status,
    type: :string,
    description: "New status: draft or scheduled",
    required: false
  parameter :scheduled_at,
    type: :string,
    description: "New scheduled time as ISO 8601, e.g. 2026-06-01T19:00:00Z. Required when changing status to scheduled.",
    required: false
  parameter :social_template_id,
    type: :integer,
    description: "Social template ID to associate with the post",
    required: false
  parameter :media_asset_ids,
    type: :array,
    description: "Ordered list of existing MediaAsset IDs. First ID becomes the primary asset. " \
          "Pass 2–10 IDs to create or reorder a carousel.",
    required: false
  parameter :collaborators,
    type: :array,
    description: "Instagram usernames to tag as collaborators (max 3, leading @ optional), e.g. " \
          "['themakeouts', 'mikeandthetvs']. Replaces the existing list; pass [] to remove all. " \
          "Omit to leave collaborators unchanged. Instagram feed posts, Reels and carousels only — not stories.",
    required: false

  def execute(id:, caption: nil, hashtags: nil, status: nil, scheduled_at: nil,
              social_template_id: nil, media_asset_ids: nil, collaborators: nil)
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

    # nil means "leave alone"; an empty array clears the list.
    unless collaborators.nil?
      return { error: "Collaborators are only supported on Instagram posts" } unless post.instagram?
      return { error: "Instagram stories don't support collaborators" } if post.story?

      begin
        usernames = Instagram::PublishOptions.normalize_collaborators(collaborators)
      rescue ArgumentError => e
        return { error: e.message }
      end

      payload = (attrs[:platform_payload] || post.platform_payload || {}).to_h
      attrs[:platform_payload] =
        usernames.any? ? payload.merge("collaborators" => usernames) : payload.except("collaborators")
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
        collaborators: post.platform_payload&.dig("collaborators") || [],
        platform_payload: post.platform_payload,
        updated_at: post.updated_at.iso8601,
        warnings: post.media_asset_reuse_warnings
      }
    else
      { errors: post.errors.full_messages }
    end
  end
end
