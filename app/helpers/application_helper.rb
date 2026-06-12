module ApplicationHelper
  include Pagy::Frontend

  def decode_name(name)
    return name if name.blank?
    CGI.unescape(name)
  end

  def sort_link_to(label, column, current_sort:, current_direction:, base_params: {}, **html_opts)
    active = current_sort == column
    next_dir = (active && current_direction == "asc") ? "desc" : "asc"
    indicator = active ? (current_direction == "asc" ? " ↑" : " ↓") : ""
    active_class = active ? "text-gray-900" : "text-gray-500 hover:text-gray-700"
    classes = "#{active_class} #{html_opts.delete(:class)}".strip

    link_to "#{label}#{indicator}", url_for(base_params.merge(sort: column, direction: next_dir, page: 1)),
      class: classes, **html_opts
  end
end
