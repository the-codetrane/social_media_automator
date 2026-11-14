module ApplicationHelper
  def decode_name(name)
    return name if name.blank?
    CGI.unescape(name)
  end

  # Pagination for a Pagy object: "Showing 1–12 of 40" beside Prev / numbered pages / Next.
  # frame: names the Turbo Frame the links navigate (and advance the URL of).
  def ui_pagy(pagy, frame: nil)
    return if pagy.pages <= 1

    nav_data = { turbo_frame: frame, turbo_action: "advance" }.compact
    pager = ui_pagination(size: :sm, aria: { label: "Pagination" }, data: nav_data) do |pages|
      if pagy.previous
        pages.with_item("‹ Prev", href: pagy.page_url(pagy.previous))
      else
        pages.with_item("‹ Prev", disabled: true)
      end
      pagy_window(pagy).each do |entry|
        if entry == :gap
          pages.with_item("…", disabled: true)
        else
          pages.with_item(entry.to_s, href: pagy.page_url(entry), active: entry == pagy.page, aria: { label: "Page #{entry}" })
        end
      end
      if pagy.next
        pages.with_item("Next ›", href: pagy.page_url(pagy.next))
      else
        pages.with_item("Next ›", disabled: true)
      end
    end

    tag.div(class: "flex flex-wrap items-center justify-between gap-3 mt-6 px-1") do
      summary = tag.p(class: "text-sm text-body-muted") do
        safe_join([ "Showing ", tag.span(pagy.from, class: "font-medium"), "–", tag.span(pagy.to, class: "font-medium"),
                    " of ", tag.span(pagy.count, class: "font-medium") ])
      end
      safe_join([ summary, pager ])
    end
  end

  # button_to drawn as a library ButtonComponent: a one-button form for actions that change
  # state. params: become hidden fields, confirm: opens the styled confirm, and the rest
  # (variant:, outline:, size:, disabled:, data: ...) go to the button.
  #
  #   <%= ui_button_to "Disconnect", admin_youtube_disconnect_path, method: :delete,
  #                    variant: :danger, outline: true, confirm: "Disconnect YouTube?" %>
  def ui_button_to(label = nil, url, method: :post, params: {}, confirm: nil, **button_options, &block)
    form_with(url: url, method: method, class: "contents", data: { turbo_confirm: confirm }.compact) do
      fields = params.map { |name, value| hidden_field_tag(name, value, id: nil) }
      safe_join(fields + [ ui_button(label, type: :submit, **button_options, &block) ])
    end
  end

  private

  # Page numbers around the current page, with :gap where pages are skipped.
  def pagy_window(pagy)
    shown = ([ 1, pagy.pages ] + ((pagy.page - 1)..(pagy.page + 1)).to_a).select { |n| n.between?(1, pagy.pages) }.uniq.sort
    shown.each_with_object([]) do |n, out|
      out << :gap if out.last && n - out.last > 1
      out << n
    end
  end
end
