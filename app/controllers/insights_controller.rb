# frozen_string_literal: true

class InsightsController < ApplicationController
  def index
    @posts = PlannedPost
      .published
      .where.not(external_post_id: nil)
      .includes(:user, :media_asset)
      .order(published_at: :desc)
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
  rescue Instagram::ApiError => e
    redirect_to insights_path, alert: "Could not load insights: #{e.message}"
  end
end
