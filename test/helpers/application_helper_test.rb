require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
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
end
