# frozen_string_literal: true

require "test_helper"

class InsightsControllerTest < ActionDispatch::IntegrationTest
  MOCK_INSIGHTS = {
    media_type:   "IMAGE",
    product_type: "FEED",
    permalink:    "https://www.instagram.com/p/test/",
    timestamp:    "2025-01-01T00:00:00Z",
    metrics: {
      "reach"              => 1200,
      "likes"              => 88,
      "comments"           => 5,
      "shares"             => 10,
      "saved"              => 20,
      "profile_visits"     => 15,
      "total_interactions" => 123
    }
  }.freeze

  def setup
    @user           = users(:one)
    @published_post = planned_posts(:published_post)
    @draft_post     = planned_posts(:draft_post)
  end

  def stub_insights_service(insights = MOCK_INSIGHTS)
    mock_svc = Object.new
    mock_svc.define_singleton_method(:fetch) { |_id| insights }
    Instagram::InsightsService.stub(:new, mock_svc) { yield }
  end

  # ---------------------------------------------------------------------------
  # Index
  # ---------------------------------------------------------------------------

  test "index redirects to sign in when not authenticated" do
    get insights_path
    assert_redirected_to new_session_path
  end

  test "index returns success when signed in" do
    sign_in_as(@user)
    get insights_path
    assert_response :success
  end

  test "index lists published posts that have an external_post_id" do
    sign_in_as(@user)
    get insights_path
    assert_match @published_post.caption, response.body
  end

  test "index links to each post insights page" do
    sign_in_as(@user)
    get insights_path
    assert_select "a[href=?]", insight_path(@published_post)
  end

  test "index does not include posts without an external_post_id" do
    sign_in_as(@user)
    get insights_path
    assert_select "a[href=?]", insight_path(@draft_post), count: 0
  end

  test "index renders timeframe toggle when posts have cached insights" do
    @published_post.update!(cached_insights: MOCK_INSIGHTS.stringify_keys)
    sign_in_as(@user)
    get insights_path
    assert_select "button[data-period='daily']",   text: "Daily"
    assert_select "button[data-period='weekly']",  text: "Weekly"
    assert_select "button[data-period='monthly']", text: "Monthly"
  end

  test "index wires stimulus controller when posts have cached insights" do
    @published_post.update!(cached_insights: MOCK_INSIGHTS.stringify_keys)
    sign_in_as(@user)
    get insights_path
    assert_select "[data-controller='insights-chart']"
    assert_select "[data-insights-chart-chart-id-value='insights-performance-chart']"
  end

  test "index embeds all three series as json data attributes" do
    @published_post.update!(cached_insights: MOCK_INSIGHTS.stringify_keys)
    sign_in_as(@user)
    get insights_path
    assert_match "data-insights-chart-daily-value",   response.body
    assert_match "data-insights-chart-weekly-value",  response.body
    assert_match "data-insights-chart-monthly-value", response.body
  end

  test "index does not render chart section when no posts have cached insights" do
    sign_in_as(@user)
    get insights_path
    assert_select "[data-controller='insights-chart']", count: 0
  end

  # ---------------------------------------------------------------------------
  # Show
  # ---------------------------------------------------------------------------

  test "show redirects to sign in when not authenticated" do
    get insight_path(@published_post)
    assert_redirected_to new_session_path
  end

  test "show redirects with alert when post has no external_post_id" do
    sign_in_as(@user)
    get insight_path(@draft_post)
    assert_redirected_to insights_path
    assert flash[:alert].present?
  end

  test "show renders insights for a published post" do
    sign_in_as(@user)
    stub_insights_service do
      get insight_path(@published_post)
    end
    assert_response :success
    assert_match "1,200", response.body
    assert_match "88",    response.body
  end

  test "show renders a chartkick bar chart" do
    sign_in_as(@user)
    stub_insights_service do
      get insight_path(@published_post)
    end
    assert_match "Chartkick", response.body
    assert_match "BarChart",  response.body
  end

  test "show displays the post caption" do
    sign_in_as(@user)
    stub_insights_service do
      get insight_path(@published_post)
    end
    assert_match @published_post.caption, response.body
  end

  test "show includes a link back to the insights index" do
    sign_in_as(@user)
    stub_insights_service do
      get insight_path(@published_post)
    end
    assert_select "a[href=?]", insights_path
  end

  test "show redirects with alert when the API returns an error" do
    sign_in_as(@user)
    error_svc = Object.new
    error_svc.define_singleton_method(:fetch) { |_| raise Instagram::ApiError.new("Bad token", code: 190) }
    Instagram::InsightsService.stub(:new, error_svc) do
      get insight_path(@published_post)
    end
    assert_redirected_to insights_path
    assert_match "Could not load insights", flash[:alert]
  end
end
