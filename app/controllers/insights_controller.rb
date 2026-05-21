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

    posts_with_insights = @posts.where.not(cached_insights: nil)
    @daily_series   = build_daily_series(posts_with_insights)
    @weekly_series  = build_weekly_series(posts_with_insights)
    @monthly_series = build_monthly_series(posts_with_insights)
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

  def build_daily_series(posts)
    cutoff = 30.days.ago.beginning_of_day
    recent = posts.select { |p| p.published_at >= cutoff }
    by_day = recent.group_by { |p| p.published_at.to_date }
    date_range = (cutoff.to_date..Date.current).to_a

    CHART_METRICS.map do |metric|
      {
        name: CHART_LABELS[metric],
        data: date_range.index_with do |date|
          (by_day[date] || []).sum do |post|
            metrics = post.cached_insights.is_a?(Hash) ? post.cached_insights : {}
            ((metrics["metrics"] || metrics)[metric] || 0).to_i
          end
        end.transform_keys { |d| d.strftime("%-m/%-d") }
      }
    end
  end

  def build_weekly_series(posts)
    weekly = posts.group_by { |p| p.published_at.beginning_of_week(:monday) }

    CHART_METRICS.map do |metric|
      {
        name: CHART_LABELS[metric],
        data: weekly.transform_values do |week_posts|
          week_posts.sum do |post|
            metrics = post.cached_insights.is_a?(Hash) ? post.cached_insights : {}
            ((metrics["metrics"] || metrics)[metric] || 0).to_i
          end
        end.transform_keys { |week| week.strftime("%-m/%-d") }
      }
    end
  end

  def build_monthly_series(posts)
    monthly = posts.group_by { |p| p.published_at.beginning_of_month }

    CHART_METRICS.map do |metric|
      {
        name: CHART_LABELS[metric],
        data: monthly.transform_values do |month_posts|
          month_posts.sum do |post|
            metrics = post.cached_insights.is_a?(Hash) ? post.cached_insights : {}
            ((metrics["metrics"] || metrics)[metric] || 0).to_i
          end
        end.transform_keys { |month| month.strftime("%b %Y") }
      }
    end
  end
end
