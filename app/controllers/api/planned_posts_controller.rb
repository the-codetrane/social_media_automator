# frozen_string_literal: true

module Api
  class PlannedPostsController < BaseController
    def create
      media_asset_id = resolve_media_asset_id(params[:planned_post])
      return if performed?

      planned_post = PlannedPost.new(planned_post_params.merge(media_asset_id: media_asset_id))

      if planned_post.save
        render json: planned_post_response(planned_post), status: :created
      else
        render json: { errors: planned_post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def bulk_create
      results = { created: [], errors: [] }

      planned_posts_params.each_with_index do |post_params, index|
        media_asset_id = resolve_media_asset_id_for_bulk(post_params, results, index)
        next if media_asset_id.nil? && results[:errors].any? { |e| e[:index] == index }

        planned_post = PlannedPost.new(post_params.except(:media_url).merge(media_asset_id: media_asset_id))

        if planned_post.save
          results[:created] << planned_post_response(planned_post)
        else
          results[:errors] << {
            index: index,
            params: post_params.except(:user_id, :media_url),
            errors: planned_post.errors.full_messages
          }
        end
      end

      status = results[:errors].any? ? :multi_status : :created
      render json: results, status: status
    end

    private

    def resolve_media_asset_id(post_params)
      # If media_asset_id is provided, use it directly
      if post_params[:media_asset_id].present?
        return post_params[:media_asset_id]
      end

      # If media_url is provided, create/find the media asset
      if post_params[:media_url].present?
        service = MediaAssetFromUrlService.new(post_params[:media_url])

        if service.call
          return service.media_asset.id
        else
          render json: { errors: [ "Media asset error: #{service.error}" ] }, status: :unprocessable_entity
          return nil
        end
      end

      # Neither provided - will fail validation
      nil
    end

    def resolve_media_asset_id_for_bulk(post_params, results, index)
      # If media_asset_id is provided, use it directly
      if post_params[:media_asset_id].present?
        return post_params[:media_asset_id]
      end

      # If media_url is provided, create/find the media asset
      if post_params[:media_url].present?
        service = MediaAssetFromUrlService.new(post_params[:media_url])

        if service.call
          return service.media_asset.id
        else
          results[:errors] << {
            index: index,
            params: post_params.except(:user_id, :media_url),
            errors: [ "Media asset error: #{service.error}" ]
          }
          return nil
        end
      end

      # Neither provided - will fail validation later
      nil
    end

    def planned_post_params
      params.require(:planned_post).permit(
        :user_id,
        :media_asset_id,
        :media_url,
        :social_template_id,
        :platform,
        :status,
        :caption,
        :hashtags,
        :scheduled_at
      ).except(:media_url)
    end

    def planned_posts_params
      params.require(:planned_posts).map do |post_params|
        post_params.permit(
          :user_id,
          :media_asset_id,
          :media_url,
          :social_template_id,
          :platform,
          :status,
          :caption,
          :hashtags,
          :scheduled_at
        )
      end
    end

    def planned_post_response(planned_post)
      {
        id: planned_post.id,
        user_id: planned_post.user_id,
        media_asset_id: planned_post.media_asset_id,
        social_template_id: planned_post.social_template_id,
        platform: planned_post.platform,
        status: planned_post.status,
        caption: planned_post.caption,
        hashtags: planned_post.hashtags,
        scheduled_at: planned_post.scheduled_at&.iso8601,
        created_at: planned_post.created_at.iso8601,
        updated_at: planned_post.updated_at.iso8601
      }
    end
  end
end
