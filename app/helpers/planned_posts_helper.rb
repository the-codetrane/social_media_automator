module PlannedPostsHelper
  STATUS_COLORS = {
    "draft"     => "bg-gray-100 text-gray-600",
    "scheduled" => "bg-blue-100 text-blue-800",
    "published" => "bg-green-100 text-green-800",
    "failed"    => "bg-red-100 text-red-700",
    "canceled"  => "bg-orange-100 text-orange-700"
  }.freeze

  PLATFORM_COLORS = {
    "instagram" => "bg-pink-100 text-pink-800",
    "youtube"   => "bg-red-100 text-red-700",
    "facebook"  => "bg-blue-100 text-blue-700",
    "tiktok"    => "bg-gray-900 text-white"
  }.freeze

  PLATFORM_DISPLAY_NAMES = {
    "instagram" => "Instagram",
    "youtube"   => "YouTube",
    "facebook"  => "Facebook",
    "tiktok"    => "TikTok"
  }.freeze

  def status_color_classes(status)
    STATUS_COLORS[status] || "bg-gray-100 text-gray-600"
  end

  def platform_color_classes(platform)
    PLATFORM_COLORS[platform] || "bg-gray-100 text-gray-600"
  end

  def platform_display_name(platform)
    PLATFORM_DISPLAY_NAMES[platform.to_s] || platform.to_s.capitalize
  end

  # What to say about a story on the show page.
  #
  # Before it publishes there is no status; afterwards Facebook reports
  # PUBLISHED or ARCHIVED, and Facebook::PostVerifier reports UNLISTED once the
  # story has dropped off the Page. Instagram reports none of these — a verified
  # IG story is described by its permalink alone.
  #
  # @param planned_post [PlannedPost]
  # @return [String]
  def story_status_label(planned_post)
    case planned_post.platform_payload&.dig("story_status")
    when Facebook::PostVerifier::UNLISTED_STATUS
      "No longer listed — a story stays live for 24 hours."
    when "ARCHIVED"
      "Archived — past its 24 hours, kept in the Page's story archive."
    when "PUBLISHED"
      "Live on the Page."
    else
      "Publishes as a story: live for 24 hours, with no caption."
    end
  end

  ASSET_GROUP_LABELS = {
    "available" => "Available",
    "reserved"  => "On another scheduled post",
    "published" => "Already published",
    "archived"  => "Archived"
  }.freeze

  # Grouped <option>s for the media asset select: free assets first, then
  # those already in use, so reuse is a deliberate choice.
  #
  # @param assets [Enumerable<MediaAsset>]
  # @param availability [Hash{Integer => String}] asset id => availability
  # @param selected [Integer, nil]
  def grouped_media_asset_options(assets, availability, selected)
    groups = assets.group_by { |asset| availability[asset.id] }
    grouped = ASSET_GROUP_LABELS.filter_map do |key, label|
      next unless groups[key]

      [ label, groups[key].map { |asset| [ asset.display_name, asset.id ] } ]
    end

    grouped_options_for_select(grouped, selected)
  end
end
