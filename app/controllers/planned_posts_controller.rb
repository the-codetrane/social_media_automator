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

  def bulk_reschedule
    amount = params[:amount].to_i.clamp(1, 10)
    unit   = %w[hours days weeks].include?(params[:unit]) ? params[:unit] : "days"
    posts  = PlannedPost.where(id: Array(params[:post_ids]).map(&:to_i))

    duration = amount.public_send(unit)
    posts.find_each { |post| post.update_column(:scheduled_at, post.scheduled_at + duration) }

    redirect_to planned_posts_path, notice: "#{posts.count} post(s) rescheduled by #{amount} #{unit}."
  end

  def bulk_destroy
    posts = PlannedPost.where(id: Array(params[:post_ids]).map(&:to_i))
    count = posts.count
    posts.destroy_all
    redirect_to planned_posts_path, notice: "#{count} post(s) deleted."
  end

  def edit
    load_form_data
  end

  def update
    post_type = params.dig(:planned_post, :post_type)
    carousel_ids = Array(params.dig(:planned_post, :carousel_asset_ids)).map(&:to_i).reject(&:zero?)

    @planned_post.assign_attributes(planned_post_params)

    if post_type == "carousel"
      if carousel_ids.size < 2
        @planned_post.errors.add(:base, "Carousel posts require at least 2 media assets")
        load_form_data
        render :edit, status: :unprocessable_entity
        return
      end
      @planned_post.media_asset_id = carousel_ids.first
      @planned_post.platform_payload = (@planned_post.platform_payload || {}).merge("carousel_asset_ids" => carousel_ids)
    else
      @planned_post.platform_payload = (@planned_post.platform_payload || {}).except("carousel_asset_ids")
    end

    if @planned_post.save
      redirect_to @planned_post, notice: "Planned post was successfully updated."
    else
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_planned_post
    @planned_post = PlannedPost.find(params[:id])
  end

  def load_form_data
    @media_assets = MediaAsset.ready.order(:external_name)
    @social_templates = SocialTemplate.order(:name)
    @carousel_asset_ids = @planned_post.platform_payload&.dig("carousel_asset_ids") || []
  end

  def planned_post_params
    params.require(:planned_post).permit(:caption, :hashtags, :scheduled_at, :status, :media_asset_id, :social_template_id)
  end
end
