module PlannedPostsHelper
  def platform_display_name(platform)
    PlatformBadgeComponent.display_name(platform)
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
