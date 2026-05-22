# frozen_string_literal: true

class FindStaleMediaAssets < RubyLLM::Tool
  description "Find media assets and posts that are over three months old (configurable). " \
              "Returns two categories: (1) assets that have never been successfully published, " \
              "and (2) published posts that have cached performance insights. " \
              "Use this to identify old content for review, archiving, or repurposing."

  param :user_id,
    type: :integer,
    desc: "Filter results to a specific user ID",
    required: false

  param :months_old,
    type: :integer,
    desc: "Minimum age threshold in months (default: 3, max: 24)",
    required: false

  def execute(user_id: nil, months_old: 3)
    cutoff = months_old.to_i.clamp(1, 24).months.ago

    {
      cutoff_date: cutoff.to_date.iso8601,
      unpublished_assets: find_unpublished(cutoff, user_id),
      published_with_insights: find_published_with_insights(cutoff, user_id)
    }
  end

  private

  def find_unpublished(cutoff, user_id)
    assets = MediaAsset.where("first_seen_at < ?", cutoff)

    # Exclude any asset that appeared in a published post — primary or carousel slot
    published_ids = Set.new
    PlannedPost.published.select(:media_asset_id, :platform_payload).each do |post|
      published_ids << post.media_asset_id
      post.platform_payload&.dig("carousel_asset_ids")&.each { |id| published_ids << id }
    end
    assets = assets.where.not(id: published_ids.to_a) if published_ids.any?

    if user_id.present?
      # Scope to assets touched by this user (draft, scheduled, failed, etc.) or never touched at all
      user_asset_ids    = PlannedPost.where(user_id: user_id).select(:media_asset_id)
      unowned_asset_ids = MediaAsset.where.not(id: PlannedPost.select(:media_asset_id)).select(:id)
      assets = assets.where(id: user_asset_ids).or(assets.where(id: unowned_asset_ids))
    end

    assets.order(:first_seen_at).map { |a| serialize_asset(a) }
  end

  def find_published_with_insights(cutoff, user_id)
    posts = PlannedPost
      .published
      .where("published_at < ?", cutoff)
      .where.not(cached_insights: nil)
      .includes(:media_asset)

    posts = posts.where(user_id: user_id) if user_id.present?

    posts.order(:published_at).map { |p| serialize_post(p) }
  end

  def serialize_asset(asset)
    posts = asset.planned_posts
    {
      asset_id:      asset.id,
      external_id:   asset.external_id,
      name:          asset.external_name,
      media_type:    asset.media_type,
      status:        asset.status,
      first_seen_at: asset.first_seen_at.to_date.iso8601,
      public_url:    asset.public_url,
      draft_count:   posts.count { |p| p.draft? },
      failed_count:  posts.count { |p| p.failed? }
    }
  end

  def serialize_post(post)
    asset   = post.media_asset
    raw     = post.cached_insights.is_a?(Hash) ? post.cached_insights : {}
    metrics = (raw["metrics"] || raw).slice(
      "reach", "likes", "comments", "shares", "saved", "total_interactions"
    )

    carousel_ids = post.platform_payload&.dig("carousel_asset_ids")
    {
      post_id:        post.id,
      platform:       post.platform,
      published_at:   post.published_at.to_date.iso8601,
      caption_snippet: post.caption&.truncate(100),
      is_carousel:    carousel_ids.present? && carousel_ids.size > 1,
      asset_id:       asset.id,
      asset_name:     asset.external_name,
      media_type:     asset.media_type,
      public_url:     asset.public_url,
      insights:       metrics
    }
  end
end
