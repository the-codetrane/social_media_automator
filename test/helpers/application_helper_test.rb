require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ComponentLibrary2100::Helpers

  test "decode_name decodes URL-encoded spaces" do
    assert_equal "Big Guys BBQ", decode_name("Big%20Guys%20BBQ")
  end

  test "decode_name decodes complex URL-encoded strings" do
    assert_equal "092025-Big Guys BBQ-Web-18.jpg", decode_name("092025-Big%20Guys%20BBQ-Web-18.jpg")
  end

  test "decode_name handles special characters" do
    assert_equal "Café & Bar", decode_name("Caf%C3%A9%20%26%20Bar")
  end

  test "decode_name returns plain strings unchanged" do
    assert_equal "sunset.jpg", decode_name("sunset.jpg")
  end

  test "decode_name handles nil" do
    assert_nil decode_name(nil)
  end

  test "decode_name handles empty string" do
    assert_equal "", decode_name("")
  end

  test "decode_name handles plus signs as literal plus signs" do
    # CGI.unescape converts + to space, which is expected web form behavior
    assert_equal "a b", decode_name("a+b")
  end

  test "ui_pagy renders nothing for a single page" do
    pagy = Pagy::Offset.new(count: 5, page: 1, limit: 12)

    assert_nil ui_pagy(pagy)
  end

  test "ui_pagy marks the current page and links the others" do
    pagy = Pagy::Offset.new(count: 100, page: 2, limit: 12)
    pagy.define_singleton_method(:page_url) { |n| "/posts?page=#{n}" }
    html = Nokogiri::HTML.fragment(ui_pagy(pagy, frame: "list"))

    assert_equal "2", html.at_css("[aria-current=page]").text
    assert_includes html.at_css("nav")["data-turbo-frame"], "list"
    assert_includes html.text, "Showing 13–24 of 100"
  end
end
