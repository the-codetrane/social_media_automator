# frozen_string_literal: true

require "test_helper"

class ChatsHelperTest < ActionView::TestCase
  test "render_markdown returns blank-safe HTML for blank input" do
    assert_equal "", render_markdown(nil)
    assert_equal "", render_markdown("")
    assert_predicate render_markdown(nil), :html_safe?
  end

  test "render_markdown renders bold and italics" do
    html = render_markdown("**bold** and *italic*")
    assert_includes html, "<strong>bold</strong>"
    assert_includes html, "<em>italic</em>"
  end

  test "render_markdown renders fenced code blocks" do
    md   = "```\nputs 'hi'\n```"
    html = render_markdown(md)
    assert_includes html, "<pre>"
    assert_includes html, "<code>"
    assert_includes html, "puts 'hi'"
  end

  test "render_markdown renders unordered lists" do
    html = render_markdown("- one\n- two")
    assert_includes html, "<ul>"
    assert_includes html, "<li>one</li>"
    assert_includes html, "<li>two</li>"
  end

  test "render_markdown renders ordered lists" do
    html = render_markdown("1. first\n2. second")
    assert_includes html, "<ol>"
    assert_includes html, "<li>first</li>"
  end

  test "render_markdown renders headings" do
    html = render_markdown("# Title")
    assert_includes html, "<h1>Title</h1>"
  end

  test "render_markdown renders tables (GFM extension)" do
    md = <<~MD
      | a | b |
      |---|---|
      | 1 | 2 |
    MD
    html = render_markdown(md)
    assert_includes html, "<table>"
    assert_includes html, "<th>a</th>"
    assert_includes html, "<td>1</td>"
  end

  test "render_markdown opens links in a new tab with safe rel attributes" do
    html = render_markdown("[link](https://example.com)")
    assert_includes html, 'href="https://example.com"'
    assert_includes html, 'target="_blank"'
    assert_includes html, 'rel="noopener noreferrer"'
  end

  test "render_markdown autolinks bare URLs" do
    html = render_markdown("Visit https://example.com today.")
    assert_includes html, 'href="https://example.com"'
  end

  test "render_markdown strips script tags from untrusted markdown" do
    html = render_markdown("hello <script>alert('xss')</script> world")
    refute_match(/<script/i, html)
    # Script body, if present at all, must be plain text — never inside a tag.
    refute_match(/<\w[^>]*>alert\(/i, html)
  end

  test "render_markdown strips disallowed event handler attributes" do
    html = render_markdown('[bad](javascript:alert(1) "x" onclick="alert(1)")')
    refute_match(/onclick=/i, html)
  end

  test "render_markdown returns an html_safe string" do
    assert_predicate render_markdown("**hi**"), :html_safe?
  end
end
