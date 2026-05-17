# frozen_string_literal: true

module ChatsHelper
  MARKDOWN_RENDERER = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(
      filter_html: false,
      no_images: false,
      no_links: false,
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    ),
    autolink:            true,
    tables:              true,
    fenced_code_blocks:  true,
    strikethrough:       true,
    superscript:         true,
    underline:           true,
    quote:               true,
    footnotes:           true,
    space_after_headers: true,
    no_intra_emphasis:   true,
    disable_indented_code_blocks: false
  )

  # Renders LLM-produced Markdown to safe HTML.
  # Output is sanitized because the source is untrusted model output.
  def render_markdown(text)
    return "".html_safe if text.blank?

    rendered = MARKDOWN_RENDERER.render(text.to_s)
    sanitize(
      rendered,
      tags: %w[p br hr a strong em b i u del s code pre blockquote ul ol li
               h1 h2 h3 h4 h5 h6 table thead tbody tr th td sup sub span div],
      attributes: %w[href target rel class title]
    )
  end
end
