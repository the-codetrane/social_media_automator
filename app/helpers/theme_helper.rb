# The app's look (the one production had before the component library) laid over the
# library's components: pale badges and avatars, a bold 2xl page title, and small uppercase
# table headings and field labels. Each helper adds classes, which the library merges over
# its defaults with tailwind_merge, then hands off to the library's helper. A class: passed
# at the call site still wins.
#
# Only the helpers are themed. Render the library's components through them (ui_badge, not
# ComponentLibrary2100::BadgeComponent.new) so they pick this up.
module ThemeHelper
  SUBTLE = {
    primary: "bg-primary-subtle-strong text-primary-emphasis",
    secondary: "bg-secondary-subtle text-secondary-emphasis",
    success: "bg-success-subtle text-success-emphasis",
    danger: "bg-danger-subtle text-danger-emphasis",
    warning: "bg-warning-subtle text-warning-emphasis",
    info: "bg-info-subtle text-info-emphasis",
    light: "bg-light-subtle text-light-emphasis",
    dark: "bg-gray-900 text-white"
  }.freeze

  BADGE = "px-2 py-0.5 text-xs leading-4 font-medium".freeze
  AVATAR = "font-semibold".freeze
  PAGE_HEADER = "[&_h1]:text-2xl [&_h1]:font-bold [&_h1]:leading-8".freeze
  TABLE = "[&_thead]:bg-surface-subtle [&_thead_th]:text-xs [&_thead_th]:font-medium [&_thead_th]:uppercase " \
          "[&_thead_th]:tracking-wide [&_thead_th]:text-body-muted [&_:is(th,td)]:px-4 [&_:is(th,td)]:py-3 " \
          "[&_tbody_:is(th,td)]:border-border-subtle [&>tbody:not(:first-child)]:border-t-0".freeze
  TABLE_CARD = "bg-surface rounded-xl shadow-sm border border-border overflow-hidden".freeze
  LABEL = "text-xs font-normal uppercase tracking-wide text-gray-400".freeze
  DESCRIPTION_LIST = "[&_dt]:text-xs [&_dt]:font-normal [&_dt]:uppercase [&_dt]:tracking-wide [&_dt]:text-gray-400".freeze
  # A record's main fields on its show page: label over value, two columns from sm.
  DETAIL_LIST = "grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6 [&_dt]:mb-1 [&_dd]:text-lg [&_dd]:text-body".freeze
  # Links as pills: the current page (or the menu holding it) filled with the primary colour,
  # and the current item inside a menu tinted.
  NAVBAR = "[&_li>a]:px-3 [&_li>a]:font-medium [&_li>a:not([aria-current]):hover]:bg-surface-muted " \
           "[&_li>a[aria-current=page]]:bg-primary [&_li>a[aria-current=page]]:text-primary-on " \
           "[&_li_button[data-current]]:bg-primary [&_li_button[data-current]]:text-primary-on " \
           "[&_li_button[data-current]]:no-underline [&_li_button]:font-medium [&_li_button]:px-3 " \
           "[&_[role=menuitem][aria-current]]:bg-primary-subtle [&_[role=menuitem][aria-current]]:text-primary-emphasis " \
           "[&_[role=menuitem][aria-current]]:font-medium".freeze

  def ui_badge(content = nil, variant: :primary, **options, &block)
    super(content, variant: variant, **themed(options, subtle(variant), BADGE), &block)
  end

  def ui_avatar(content = nil, variant: :secondary, **options, &block)
    super(content, variant: variant, **themed(options, subtle(variant), AVATAR), &block)
  end

  def ui_page_header(content = nil, **options, &block)
    super(content, **themed(options, PAGE_HEADER), &block)
  end

  # In a white card, as every table in the app is. card: false for one already inside a card.
  def ui_table(content = nil, card: true, **options, &block)
    table = super(content, **themed(options, TABLE), &block)
    card ? tag.div(table, class: TABLE_CARD) : table
  end

  def ui_description_list(content = nil, **options, &block)
    super(content, **themed(options, DESCRIPTION_LIST), &block)
  end

  def ui_detail_list(**options, &block)
    ui_description_list(dividers: false, **themed(options, DETAIL_LIST), &block)
  end

  def ui_navbar(content = nil, **options, &block)
    super(content, **themed(options, NAVBAR), &block)
  end

  # Pale filter chips and a grey segmented control: .app-toggle in application.css.
  def ui_toggle_group(content = nil, style: :pills, **options, &block)
    super(content, style: style, **themed(options, "app-toggle app-toggle-#{style}"), &block)
  end

  private

  def subtle(variant) = SUBTLE.fetch(variant.to_sym, SUBTLE[:secondary])

  # The theme's classes first, so the call site's class: wins the merge.
  def themed(options, *classes)
    options.merge(class: [ *classes, options[:class] ].compact.join(" "))
  end
end
