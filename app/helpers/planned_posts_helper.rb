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
end
