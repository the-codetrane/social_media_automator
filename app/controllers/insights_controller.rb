# frozen_string_literal: true

class InsightsController < ApplicationController
  CHART_METRICS = %w[reach likes comments shares saved profile_visits total_interactions].freeze
  CHART_LABELS = {
    "reach"               => "Reach",
    "likes"               => "Likes",
    "comments"            => "Comments",
    "shares"              => "Shares",
    "saved"               => "Saves",
    "profile_visits"      => "Profile Visits",
    "total_interactions"  => "Total Interactions"
  }.freeze

  def index
    @posts = PlannedPost
      .published
      .where.not(external_post_id: nil)
      .includes(:user, :media_asset)
      .order(published_at: :desc)

    @chart_series = build_weekly_series(@posts.where.not(cached_insights: nil))
  end

  def show
    @post = PlannedPost.find(params[:id])

    unless @post.external_post_id.present?
      redirect_to insights_path, alert: "This post has not been published yet."
      return
    end

    @insights = if @post.facebook?
      Facebook::InsightsService.new(@post.user).fetch(@post)
    else
      Instagram::InsightsService.new(@post.user).fetch(@post.external_post_id)
    end

    @post.update_column(:cached_insights, @insights)
  rescue Instagram::ApiError => e
    redirect_to insights_path, alert: "Could not load insights: #{e.message}"
  end

  private

  def build_weekly_series(posts)
    weekly = posts.group_by { |p| p.published_at.beginning_of_week(:monday) }

    CHART_METRICS.map do |metric|
      {
        name: CHART_LABELS[metric],
        data: weekly.transform_values do |week_posts|
          week_posts.sum do |post|
            metrics = post.cached_insights.is_a?(Hash) ? post.cached_insights : {}
            metrics_hash = metrics["metrics"] || metrics
            (metrics_hash[metric] || 0).to_i
          end
        end.transform_keys { |week| week.strftime("%-m/%-d") }
      }
    end
  end
end
