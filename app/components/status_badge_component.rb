# A pill for a PlannedPost or MediaAsset status. kind: is :post or :media.
class StatusBadgeComponent < ComponentLibrary2100::BadgeComponent
  VARIANTS = {
    post: {
      "draft" => :secondary,
      "scheduled" => :primary,
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
    super(variant: VARIANTS.fetch(kind).fetch(@status, :secondary), pill: true, **html_options)
  end

  def content = @status.humanize
end
