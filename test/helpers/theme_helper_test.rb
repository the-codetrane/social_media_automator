require "test_helper"

# Rendered through a real view context, where the app's helpers sit in front of the
# library's, so ThemeHelper's super reaches the library as it does in the app.
class ThemeHelperTest < ActiveSupport::TestCase
  setup do
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    @view = controller.view_context
  end

  def html(fragment) = Nokogiri::HTML5.fragment(fragment)

  test "badges are pale with medium weight, replacing the library's solid fill" do
    badge = html(@view.ui_badge("Admin", variant: :success)).at_css("span")

    assert_includes badge["class"].split, "bg-success-subtle"
    assert_includes badge["class"].split, "font-medium"
    assert_not_includes badge["class"].split, "bg-success"
    assert_not_includes badge["class"].split, "font-bold"
  end

  test "a class from the call site still wins" do
    badge = html(@view.ui_badge("Admin", variant: :success, class: "bg-danger-subtle")).at_css("span")

    assert_includes badge["class"].split, "bg-danger-subtle"
    assert_not_includes badge["class"].split, "bg-success-subtle"
  end

  test "tables sit in a card unless card: false" do
    assert html(@view.ui_table { "" }).at_css("div.rounded-xl > table")
    assert_nil html(@view.ui_table(card: false) { "" }).at_css("div.rounded-xl")
  end

  test "toggle groups get the hooks for their style" do
    group = html(@view.ui_toggle_group(name: "status", type: :radio, style: :segmented, label: "Status") { "" }).at_css("fieldset")

    assert_includes group["class"].split, "app-toggle"
    assert_includes group["class"].split, "app-toggle-segmented"
  end

  test "detail lists are a two-column grid without dividers" do
    list = html(@view.ui_detail_list { |dl| dl.with_item(term: "Owner", description: "Ada") }).at_css("dl")

    assert_includes list["class"].split, "sm:grid-cols-2"
    assert_equal "Ada", list.at_css("dd").text.strip
  end
end
