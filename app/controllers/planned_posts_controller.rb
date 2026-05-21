# frozen_string_literal: true

class PlannedPostsController < ApplicationController
  before_action :set_planned_post, only: %i[show edit update publish verify]

  def index
    @platforms = Array(params[:platforms]).map(&:to_s).select { |p| PlannedPost.platforms.key?(p) }
    @status    = PlannedPost.statuses.key?(params[:status]) ? params[:status] : "scheduled"

    scope = PlannedPost.includes(:user, :media_asset, :social_template)
    scope = scope.where(platform: @platforms) if @platforms.any?
    scope = scope.where(status: @status)

    order_col = @status == "published" ? :published_at : :scheduled_at
    @planned_posts = scope.order(order_col => :asc)
  end

  def show
    carousel_ids = @planned_post.platform_payload&.dig("carousel_asset_ids")
    @carousel_assets = MediaAsset.where(id: carousel_ids).index_by(&:id).values_at(*carousel_ids).compact if carousel_ids.present?
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

  def verify
    if @planned_post.published? && @planned_post.external_post_id.present?
      VerifyPublishedPostJob.perform_later(@planned_post.id)
      redirect_to @planned_post, notice: "Verification has been queued."
    else
      redirect_to @planned_post, alert: "Post must be published before it can be verified."
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
