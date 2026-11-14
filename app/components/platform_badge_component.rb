# A pill naming a social platform, in the platform's brand colour (the --color-<platform>
# tokens in app/assets/tailwind/application.css).
class PlatformBadgeComponent < ComponentLibrary2100::BadgeComponent
  NAMES = {
    "instagram" => "Instagram",
    "youtube" => "YouTube",
    "facebook" => "Facebook",
    "tiktok" => "TikTok"
  }.freeze

  COLORS = {
    "instagram" => "bg-instagram border-instagram",
    "youtube" => "bg-youtube border-youtube",
    "facebook" => "bg-facebook border-facebook",
    "tiktok" => "bg-tiktok border-tiktok"
  }.freeze

  def self.display_name(platform)
    NAMES[platform.to_s] || platform.to_s.humanize
  end

  def initialize(platform:, **html_options)
    @platform = platform.to_s
    color = COLORS.fetch(@platform, "bg-secondary border-secondary")
    super(variant: :dark, pill: true, **html_options.merge(class: [ color, "text-white", html_options[:class] ]))
  end

  def content = self.class.display_name(@platform)
end
