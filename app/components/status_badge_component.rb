# A pill for a PlannedPost or MediaAsset status. kind: is :post or :media.
class StatusBadgeComponent < ComponentLibrary2100::BadgeComponent
  VARIANTS = {
    post: {
      "draft" => :secondary,
      "scheduled" => :info,
      "published" => :success,
      "failed" => :danger,
      "canceled" => :warning
    },
    media: {
      "discovered" => :warning,
      "processed" => :success,
      "failed" => :danger
    }
  }.freeze

  def initialize(status:, kind: :post, **html_options)
    @status = status.to_s
    variant = VARIANTS.fetch(kind).fetch(@status, :secondary)
    classes = [ ThemeHelper::SUBTLE.fetch(variant), ThemeHelper::BADGE, html_options[:class] ]
    super(variant: variant, pill: true, **html_options.merge(class: classes))
  end

  def content = @status.humanize
end
