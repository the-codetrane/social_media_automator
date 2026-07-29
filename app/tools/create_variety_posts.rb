class CreateVarietyPosts < RubyLLM::Tool
  description "Select media assets with diversity across venue location, featured people, and visual " \
              "content — then create planned posts. Avoids repeating the same venue, the same person, " \
              "recently-used assets, or assets that look like burst shots of the same moment (judged " \
              "by upload time and filename sequence). Assets should be enriched first via " \
              "enrich_media_assets. Optionally checks the selected set for visually similar images."

  param :user_id,
    type: :integer,
    desc: "The current user's ID"

  param :platform,
    type: :string,
    desc: "Target platform: instagram, youtube, facebook, or tiktok"

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
    desc: "Restrict to 'image' or 'video'. Leave blank for both. Ignored for tiktok, " \
          "which is always restricted to video.",
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

  param :min_spacing_minutes,
    type: :integer,
    desc: "Minimum gap between the first_seen_at timestamps of any two selected assets, in minutes " \
          "(default: 30, 0 to disable). Prevents picking multiple shots from the same burst/moment. " \
          "A candidate also passes if it clears the filename-sequence spacing check instead (see " \
          "select_varied) — that catches bursts that a single bulk upload collapsed to near-identical " \
          "first_seen_at values. Falls back to ignoring both checks only if there aren't enough " \
          "spaced-out candidates left to fill the requested count.",
    required: false

  def execute(user_id:, platform:, count:, caption:, hashtags:,
              status: "draft", schedule_start: nil, schedule_interval_hours: 24,
              media_type: nil, exclude_asset_ids: nil, check_similarity: false, recency_days: 30,
              min_spacing_minutes: 30)
    count = [ [ count.to_i, 1 ].max, 20 ].min
    recency_days = [ [ recency_days.to_i, 1 ].max, 365 ].min
    min_spacing_minutes = min_spacing_minutes.to_i.clamp(0, 1440)

    # TikTok rejects image posts, and PlannedPost validates that — so selecting
    # images here would just produce a batch of save failures.
    media_type = "video" if platform.to_s == "tiktok"

    candidates = load_candidates(user_id, media_type, exclude_asset_ids, recency_days)
    if candidates.empty?
      return { error: "No eligible processed video assets found for TikTok." } if platform.to_s == "tiktok"
      return { error: "No eligible processed assets found. Run enrich_media_assets first." }
    end

    selected = select_varied(candidates, count, min_spacing_minutes)

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

  # A whole shoot is often bulk-uploaded in one sitting, which collapses first_seen_at
  # gaps to near-zero regardless of how far apart the shots actually were — so time alone
  # can't be trusted to catch bursts. Camera-sequential filenames (IMG_1234, IMG_1235...)
  # survive that bulk upload untouched, so a candidate only needs to clear ONE of the two
  # signals to count as "spaced out" from a given selected asset.
  MIN_FILENAME_SPACING = 2

  # Greedy variety selection: each round pick the candidate with the lowest repetition score.
  # Venue weight (3×) > people weight (1×) so geography is the primary diversity axis.
  # Before scoring, candidates too close to an already-selected asset by BOTH the time and
  # filename-sequence checks are excluded — they're likely burst shots of the same moment.
  # That filter is dropped for a round only if it would otherwise leave no candidate to pick.
  def select_varied(candidates, count, min_spacing_minutes = 30)
    return candidates.sample(count) if candidates.size <= count

    name_position = candidates.sort_by { |a| natural_sort_key(a.external_name) }
                               .each_with_index.to_h { |a, i| [ a.id, i ] }

    selected     = []
    used_venues  = Hash.new(0)
    used_people  = Hash.new(0)
    time_gap     = min_spacing_minutes.minutes

    count.times do
      remaining = candidates.reject { |a| selected.include?(a) }
      break if remaining.empty?

      spaced = remaining.select { |a| spaced_out?(a, selected, time_gap, name_position) }
      pool = spaced.presence || remaining

      best = pool.min_by do |asset|
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

  def spaced_out?(asset, selected, time_gap, name_position)
    selected.all? do |s|
      by_time = time_gap.positive? && (asset.first_seen_at - s.first_seen_at).abs >= time_gap
      by_name = (name_position[asset.id] - name_position[s.id]).abs > MIN_FILENAME_SPACING
      by_time || by_name
    end
  end

  # Splits a filename into text/number runs so "img2" sorts before "img10" — plain
  # string sort would put "img10" first. Each token is tagged [0, str] or [1, int] so
  # mixed-type comparisons between same-position tokens never raise.
  def natural_sort_key(name)
    name.to_s.scan(/\d+|\D+/).map { |chunk| chunk.match?(/\A\d+\z/) ? [ 1, chunk.to_i ] : [ 0, chunk ] }
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
