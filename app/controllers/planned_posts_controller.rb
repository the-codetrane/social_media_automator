# frozen_string_literal: true

class PlannedPostsController < ApplicationController
  before_action :set_planned_post, only: %i[show edit update publish]

  def index
    @planned_posts = PlannedPost.includes(:user, :media_asset, :social_template).order(created_at: :desc)
  end

  def show
  end

  def publish
    case @planned_post.platform
    when "instagram"
      PublishInstagramPostJob.perform_later(@planned_post.id)
      redirect_to @planned_post, notice: "Publishing to Instagram has been queued."
    when "facebook"
      PublishFacebookPostJob.perform_later(@planned_post.id)
      redirect_to @planned_post, notice: "Publishing to Facebook has been queued."
    else
      redirect_to @planned_post, alert: "Publishing is not supported for #{@planned_post.platform} yet."
    end
  end

  def edit
    @media_assets = MediaAsset.order(:external_name)
    @social_templates = SocialTemplate.order(:name)
  end

  def update
    if @planned_post.update(planned_post_params)
      redirect_to @planned_post, notice: "Planned post was successfully updated."
    else
      @media_assets = MediaAsset.order(:external_name)
      @social_templates = SocialTemplate.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_planned_post
    @planned_post = PlannedPost.find(params[:id])
  end

  def planned_post_params
    params.require(:planned_post).permit(:caption, :hashtags, :scheduled_at, :status, :media_asset_id, :social_template_id)
  end
end
