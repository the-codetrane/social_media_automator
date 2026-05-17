# frozen_string_literal: true

module Facebook
  class InsightsService
    FEED_METRICS = %w[
      post_impressions post_impressions_unique
      post_impressions_organic post_impressions_paid
      post_clicks
      post_reactions_like_total post_reactions_love_total
      post_reactions_wow_total post_reactions_haha_total
      post_reactions_sorry_total post_reactions_anger_total
    ].freeze

    VIDEO_METRICS = (FEED_METRICS + %w[
      post_video_views post_video_views_unique
      post_video_avg_time_watched post_video_view_time
    ]).freeze

    METRIC_LABELS = {
      "post_impressions"            => "Total Impressions",
      "post_impressions_unique"     => "Reach",
      "post_impressions_organic"    => "Organic Impressions",
      "post_impressions_paid"       => "Paid Impressions",
      "post_clicks"                 => "Post Clicks",
      "post_reactions_like_total"   => "Likes",
      "post_reactions_love_total"   => "Love",
      "post_reactions_wow_total"    => "Wow",
      "post_reactions_haha_total"   => "Haha",
      "post_reactions_sorry_total"  => "Sorry",
      "post_reactions_anger_total"  => "Angry",
      "post_video_views"            => "Video Views (3s+)",
      "post_video_views_unique"     => "Unique Video Views",
      "post_video_avg_time_watched" => "Avg Watch Time",
      "post_video_view_time"        => "Total View Time"
    }.freeze

    REACTION_KEYS = %w[
      post_reactions_like_total post_reactions_love_total
      post_reactions_wow_total post_reactions_haha_total
      post_reactions_sorry_total post_reactions_anger_total
    ].freeze

    def initialize(user)
      @user    = user
      @page_id = user.instagram_page_id.presence ||
        raise(Instagram::ApiError, "User #{user.id} has no Facebook page_id set")
    end

    def fetch(post)
      page_token   = fetch_page_access_token
      client       = Instagram::ApiClient.new(@user, access_token: page_token)
      media_type   = infer_media_type(post)
      metrics_list = media_type == "VIDEO" ? VIDEO_METRICS : FEED_METRICS

      insights_response = client.get(
        "#{post.external_post_id}/insights",
        metric: metrics_list.join(","),
        period: "lifetime"
      )

      post_info = client.get(post.external_post_id, fields: "permalink_url,created_time")

      {
        media_type: media_type,
        permalink:  post_info["permalink_url"],
        timestamp:  post_info["created_time"],
        metrics:    parse_metrics(insights_response["data"] || [])
      }
    end

    private

    def infer_media_type(post)
      return "VIDEO" if post.media_asset&.video?
      return "PHOTO" if post.media_asset&.image?
      "FEED"
    end

    def fetch_page_access_token
      result = Instagram::ApiClient.new(@user).get(@page_id, fields: "access_token")
      token  = result["access_token"]
      raise Instagram::ApiError, "Could not retrieve Page access token for page #{@page_id}" if token.blank?
      token
    end

    def parse_metrics(data)
      data.each_with_object({}) do |metric, hash|
        value = metric.dig("values", 0, "value") ||
                metric.dig("total_value", "value") ||
                0
        hash[metric["name"]] = value
      end
    end
  end
end
