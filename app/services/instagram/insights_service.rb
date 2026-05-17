# frozen_string_literal: true

module Instagram
  class InsightsService
    FEED_METRICS = %w[reach likes comments shares saved profile_visits total_interactions].freeze
    REEL_METRICS = %w[reach likes comments shares saved ig_reels_avg_watch_time ig_reels_video_view_total_time total_interactions].freeze
    STORY_METRICS = %w[reach shares replies profile_visits follows].freeze

    METRIC_LABELS = {
      "reach"                          => "Reach",
      "likes"                          => "Likes",
      "comments"                       => "Comments",
      "shares"                         => "Shares",
      "saved"                          => "Saves",
      "profile_visits"                 => "Profile Visits",
      "total_interactions"             => "Total Interactions",
      "ig_reels_avg_watch_time"        => "Avg Watch Time",
      "ig_reels_video_view_total_time" => "Total View Time",
      "replies"                        => "Replies",
      "follows"                        => "Follows"
    }.freeze

    def initialize(user)
      @client = Instagram::ApiClient.new(user)
    end

    # Returns a hash with media metadata and a flat metrics hash.
    def fetch(external_post_id)
      media = @client.get(external_post_id, fields: "media_type,media_product_type,timestamp,permalink")
      product_type = media["media_product_type"] || "FEED"
      metrics_list = metrics_for(product_type)

      insights_response = @client.get(
        "#{external_post_id}/insights",
        metric: metrics_list.join(","),
        period: "lifetime"
      )

      {
        media_type:   media["media_type"],
        product_type: product_type,
        permalink:    media["permalink"],
        timestamp:    media["timestamp"],
        metrics:      parse_metrics(insights_response["data"] || [])
      }
    end

    private

    def metrics_for(product_type)
      case product_type
      when "REELS" then REEL_METRICS
      when "STORY" then STORY_METRICS
      else              FEED_METRICS
      end
    end

    def parse_metrics(data)
      data.each_with_object({}) do |metric, hash|
        value = metric.dig("total_value", "value") ||
                metric.dig("values", 0, "value") ||
                0
        hash[metric["name"]] = value
      end
    end
  end
end
