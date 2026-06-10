class CreateVarietyPosts < RubyLLM::Tool
  description "Select media assets with diversity across venue location, featured people, and visual " \
              "content — then create planned posts. Avoids repeating the same venue, the same person, " \
              "or recently-used assets. Assets should be enriched first via enrich_media_assets. " \
              "Optionally checks the selected set for visually similar images."

  param :user_id,
    type: :integer,
    desc: "The current user's ID"

  param :platform,
    type: :string,
    desc: "Target platform: instagram, youtube, or facebook"

  param :count,
    type: :integer,
    desc: "Number of posts to create (1–20)"

  param :caption,
    type: :string,
    desc: "Caption text to use for all posts"

  param :hashtags,
    type: :string,
    desc: "Hashtag string to append, e.g. '#live #music #band'"

  param :status,
    type: :string,
    desc: "Post status: draft or scheduled (default: draft)",
    required: false

  param :schedule_start,
    type: :string,
    desc: "ISO 8601 datetime for the first scheduled post, e.g. 2026-06-15T18:00:00Z. Required when status is scheduled.",
    required: false

  param :schedule_interval_hours,
    type: :integer,
    desc: "Hours between each scheduled post (default: 24)",
    required: false

  param :media_type,
    type: :string,
    desc: "Restrict to 'image' or 'video'. Leave blank for both.",
    required: false

  param :exclude_asset_ids,
    type: :array,
    desc: "Asset IDs to skip during selection",
    required: false

  param :check_similarity,
    type: :boolean,
    desc: "Run visual similarity check on selected images and flag near-duplicates (default: false). " \
          "Posts are still created — similar pairs are reported so you can swap manually.",
    required: false

  param :recency_days,
    type: :integer,
    desc: "How many days back to consider an asset 'recently used' (default: 30)",
    required: false

  def execute(user_id:, platform:, count:, caption:, hashtags:,
              status: "draft", schedule_start: nil, schedule_interval_hours: 24,
              media_type: nil, exclude_asset_ids: nil, check_similarity: false, recency_days: 30)
    count = [ [ count.to_i, 1 ].max, 20 ].min
    recency_days = [ [ recency_days.to_i, 1 ].max, 365 ].min

    candidates = load_candidates(user_id, media_type, exclude_asset_ids, recency_days)
    return { error: "No eligible processed assets found. Run enrich_media_assets first." } if candidates.empty?

    selected = select_varied(candidates, count)

    similar_pairs = []
    if check_similarity && selected.size >= 2
      image_urls = selected.select(&:image?).filter_map(&:public_url)
      if image_urls.size >= 2
        result = Vision::SimilarityCheckerService.new.call(image_urls)
        similar_pairs = result if result.is_a?(Array)
      end
    end

    base_time   = schedule_start.present? ? Time.zone.parse(schedule_start) : nil
    interval_h  = schedule_interval_hours.to_i.clamp(1, 8760)
    posts_created = []
    errors = []

    selected.each_with_index do |asset, i|
      scheduled_at = base_time ? base_time + (i * interval_h).hours : nil

      post = PlannedPost.new(
        user_id:        user_id,
        platform:       platform,
        media_asset_id: asset.id,
        caption:        caption,
        hashtags:       hashtags,
        status:         status,
        scheduled_at:   scheduled_at
      )

      if post.save
        posts_created << {
          post_id:      post.id,
          asset_id:     asset.id,
          venue:        venue_label(asset),
          people:       person_names(asset),
          scheduled_at: post.scheduled_at&.iso8601
        }
      else
        errors << { asset_id: asset.id, errors: post.errors.full_messages }
      end
    end

    response = { created: posts_created.size, posts: posts_created }
    response[:errors]        = errors          if errors.any?
    response[:similar_pairs] = similar_pairs   if similar_pairs.any?
    response[:similarity_warning] = "#{similar_pairs.size} visually similar pair(s) detected — consider replacing one from each pair." if similar_pairs.any?
    response
  end

  private

  def load_candidates(user_id, media_type, exclude_asset_ids, recency_days)
    assets = MediaAsset.ready
    assets = assets.images if media_type == "image"
    assets = assets.videos if media_type == "video"

    used_ids = recently_used_asset_ids(user_id, recency_days)
    assets = assets.where.not(id: used_ids) if used_ids.any?
    assets = assets.where.not(id: Array(exclude_asset_ids).map(&:to_i)) if exclude_asset_ids.present?

    assets.to_a
  end

  def recently_used_asset_ids(user_id, recency_days)
    cutoff = recency_days.days.ago
    used = []
    PlannedPost.where(user_id: user_id)
      .where("created_at > ?", cutoff)
      .where.not(status: :canceled)
      .select(:media_asset_id, :platform_payload)
      .each do |post|
        used << post.media_asset_id
        post.platform_payload&.dig("carousel_asset_ids")&.each { |id| used << id }
      end
    used.compact.uniq
  end

  # Greedy variety selection: each round pick the candidate with the lowest repetition score.
  # Venue weight (3×) > people weight (1×) so geography is the primary diversity axis.
  def select_varied(candidates, count)
    return candidates.sample(count) if candidates.size <= count

    selected   = []
    used_venues = Hash.new(0)
    used_people = Hash.new(0)

    count.times do
      remaining = candidates.reject { |a| selected.include?(a) }
      break if remaining.empty?

      best = remaining.min_by do |asset|
        venue_score  = used_venues[venue_key(asset)]
        person_score = person_names(asset).sum { |name| used_people[name] }
        venue_score * 3 + person_score
      end

      selected << best
      used_venues[venue_key(best)] += 1
      person_names(best).each { |name| used_people[name] += 1 }
    end

    selected
  end

  def venue_key(asset)
    if asset.city.present?
      "#{asset.city},#{asset.state}"
    elsif asset.latitude.present?
      # ~1 km grid cell
      "#{asset.latitude.round(2)},#{asset.longitude.round(2)}"
    else
      "unknown"
    end
  end

  def venue_label(asset)
    [ asset.address.presence, asset.city.presence, asset.state.presence ]
      .compact.first || (asset.latitude.present? ? "#{asset.latitude.round(4)},#{asset.longitude.round(4)}" : nil)
  end

  def person_names(asset)
    Array(asset.identified_people).filter_map { |p| p["name"] }
  end
end
