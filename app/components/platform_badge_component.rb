# A pill naming a social platform, in the platform's colours (the --color-<platform>-subtle
# and -emphasis tokens in app/assets/tailwind/application.css).
class PlatformBadgeComponent < ComponentLibrary2100::BadgeComponent
  NAMES = {
    "instagram" => "Instagram",
    "youtube" => "YouTube",
    "facebook" => "Facebook",
    "tiktok" => "TikTok"
  }.freeze

  COLORS = {
    "instagram" => "bg-instagram-subtle text-instagram-emphasis",
    "youtube" => "bg-youtube-subtle text-youtube-emphasis",
    "facebook" => "bg-facebook-subtle text-facebook-emphasis",
    "tiktok" => "bg-tiktok-subtle text-tiktok-emphasis"
  }.freeze

  def self.display_name(platform)
    NAMES[platform.to_s] || platform.to_s.humanize
  end

  def initialize(platform:, **html_options)
    @platform = platform.to_s
    color = COLORS.fetch(@platform, ThemeHelper::SUBTLE[:secondary])
    super(variant: :secondary, pill: true, **html_options.merge(class: [ color, ThemeHelper::BADGE, html_options[:class] ]))
  end

  def content = self.class.display_name(@platform)
end
