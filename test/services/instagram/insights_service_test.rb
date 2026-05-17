# frozen_string_literal: true

require "test_helper"

module Instagram
  class InsightsServiceTest < ActiveSupport::TestCase
    def setup
      @user     = users(:one)
      @service  = Instagram::InsightsService.new(@user)
      @media_id = "17846368219941196"
    end

    # Builds a mock client whose first call returns media_resp and second returns insights_resp.
    def stub_client(media_resp, insights_resp)
      call_count = 0
      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |_path, _params = {}|
        call_count += 1
        call_count == 1 ? media_resp : insights_resp
      end
      @service.instance_variable_set(:@client, mock_client)
    end

    # ---------------------------------------------------------------------------
    # Request shape
    # ---------------------------------------------------------------------------

    test "fetch requests media_product_type field from the media endpoint" do
      captured_params = nil
      mock_client = Object.new
      call_count = 0
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        call_count += 1
        if call_count == 1
          captured_params = params
          { "media_type" => "IMAGE", "media_product_type" => "FEED" }
        else
          { "data" => [] }
        end
      end
      @service.instance_variable_set(:@client, mock_client)
      @service.fetch(@media_id)

      assert_includes captured_params[:fields], "media_product_type"
    end

    # ---------------------------------------------------------------------------
    # Metric selection by product type
    # ---------------------------------------------------------------------------

    test "fetch sends FEED_METRICS for FEED posts" do
      captured_metrics = nil
      mock_client = Object.new
      call_count = 0
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        call_count += 1
        if call_count == 1
          { "media_type" => "IMAGE", "media_product_type" => "FEED" }
        else
          captured_metrics = params[:metric]
          { "data" => [] }
        end
      end
      @service.instance_variable_set(:@client, mock_client)
      @service.fetch(@media_id)

      assert_includes captured_metrics, "reach"
      assert_includes captured_metrics, "saved"
      refute_includes captured_metrics, "ig_reels_avg_watch_time"
    end

    test "fetch sends REEL_METRICS for REELS posts" do
      captured_metrics = nil
      mock_client = Object.new
      call_count = 0
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        call_count += 1
        if call_count == 1
          { "media_type" => "VIDEO", "media_product_type" => "REELS" }
        else
          captured_metrics = params[:metric]
          { "data" => [] }
        end
      end
      @service.instance_variable_set(:@client, mock_client)
      @service.fetch(@media_id)

      assert_includes captured_metrics, "ig_reels_avg_watch_time"
      assert_includes captured_metrics, "ig_reels_video_view_total_time"
    end

    test "fetch sends STORY_METRICS for STORY posts" do
      captured_metrics = nil
      mock_client = Object.new
      call_count = 0
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        call_count += 1
        if call_count == 1
          { "media_type" => "IMAGE", "media_product_type" => "STORY" }
        else
          captured_metrics = params[:metric]
          { "data" => [] }
        end
      end
      @service.instance_variable_set(:@client, mock_client)
      @service.fetch(@media_id)

      assert_includes captured_metrics, "replies"
      refute_includes captured_metrics, "saved"
    end

    test "fetch defaults to FEED_METRICS when media_product_type is absent" do
      captured_metrics = nil
      mock_client = Object.new
      call_count = 0
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        call_count += 1
        if call_count == 1
          { "media_type" => "IMAGE" }
        else
          captured_metrics = params[:metric]
          { "data" => [] }
        end
      end
      @service.instance_variable_set(:@client, mock_client)
      @service.fetch(@media_id)

      assert_includes captured_metrics, "likes"
    end

    # ---------------------------------------------------------------------------
    # Metric parsing
    # ---------------------------------------------------------------------------

    test "fetch reads value from total_value when present" do
      stub_client(
        { "media_type" => "IMAGE", "media_product_type" => "FEED" },
        { "data" => [ { "name" => "reach", "total_value" => { "value" => 500 }, "values" => [] } ] }
      )
      result = @service.fetch(@media_id)

      assert_equal 500, result[:metrics]["reach"]
    end

    test "fetch falls back to values array when total_value is absent" do
      stub_client(
        { "media_type" => "IMAGE", "media_product_type" => "FEED" },
        { "data" => [ { "name" => "likes", "values" => [ { "value" => 42 } ] } ] }
      )
      result = @service.fetch(@media_id)

      assert_equal 42, result[:metrics]["likes"]
    end

    test "fetch includes product_type and permalink in returned hash" do
      stub_client(
        { "media_type" => "IMAGE", "media_product_type" => "FEED", "permalink" => "https://www.instagram.com/p/abc/" },
        { "data" => [] }
      )
      result = @service.fetch(@media_id)

      assert_equal "FEED", result[:product_type]
      assert_equal "https://www.instagram.com/p/abc/", result[:permalink]
    end

    # ---------------------------------------------------------------------------
    # Error propagation
    # ---------------------------------------------------------------------------

    test "fetch propagates ApiError from the client" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) { |*_| raise Instagram::ApiError.new("Unauthorized", code: 190) }
      @service.instance_variable_set(:@client, mock_client)

      err = assert_raises(Instagram::ApiError) { @service.fetch(@media_id) }
      assert_equal 190, err.code
    end
  end
end
