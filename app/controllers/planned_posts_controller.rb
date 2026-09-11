# frozen_string_literal: true

class PlannedPostsController < ApplicationController
  before_action :set_planned_post, only: %i[show edit update publish verify audio_search collaborator_search]

  SORT_COLUMNS = %w[platform scheduled_at published_at created_at].freeze

  PUBLISH_JOBS = {
    "instagram" => PublishInstagramPostJob,
    "facebook"  => PublishFacebookPostJob,
    "youtube"   => PublishYouTubePostJob,
    "tiktok"    => PublishTikTokPostJob
  }.freeze

  def index
    @platforms = Array(params[:platforms]).map(&:to_s).select { |p| PlannedPost.platforms.key?(p) }
    @status    = PlannedPost.statuses.key?(params[:status]) ? params[:status] : "scheduled"

    default_sort = @status == "published" ? "published_at" : "scheduled_at"
    @sort      = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : default_sort
    @direction = params[:direction] == "desc" ? "desc" : "asc"

    scope = PlannedPost.includes(:user, :media_asset, :social_template)
    scope = scope.where(platform: @platforms) if @platforms.any?
    scope = scope.where(status: @status)

    @pagy, @planned_posts = pagy(scope.order(@sort => @direction))
  end

  def show
    carousel_ids = @planned_post.platform_payload&.dig("carousel_asset_ids")
    @carousel_assets = MediaAsset.where(id: carousel_ids).index_by(&:id).values_at(*carousel_ids).compact if carousel_ids.present?

    order_col = @planned_post.published? ? :published_at : :scheduled_at
    order_val = @planned_post.send(order_col)
    base = PlannedPost.where(status: @planned_post.status)
    @prev_post = base.where("#{order_col} < ?", order_val).order(order_col => :desc).first
    @next_post = base.where("#{order_col} > ?", order_val).order(order_col => :asc).first
  end

  def publish
    job = PUBLISH_JOBS[@planned_post.platform]

    if job.nil?
      return redirect_to @planned_post,
        alert: "Publishing is not supported for #{@planned_post.platform} yet."
    end

    # Checked before enqueuing: otherwise the job runs, the API client raises on
    # the missing token, and the post is discarded as failed with the reason
    # visible only in the server log.
    unless @planned_post.platform_connected?
      return redirect_to @planned_post,
        alert: "#{platform_name} is not connected. Connect the account in Admin, then publish again."
    end

    job.perform_later(@planned_post.id)
    redirect_to @planned_post, notice: "Publishing to #{platform_name} has been queued."
  end

  def verify
    if @planned_post.published? && @planned_post.external_post_id.present?
      VerifyPublishedPostJob.perform_later(@planned_post.id)
      redirect_to @planned_post, notice: "Verification has been queued."
    else
      redirect_to @planned_post, alert: "Post must be published before it can be verified."
    end
  end

  # JSON — powers the Reels audio picker on the edit form.
  # Searches Instagram's audio catalogue on behalf of the post's owner.
  def audio_search
    audio_type = Instagram::AudioService::AUDIO_TYPES.include?(params[:audio_type]) ? params[:audio_type] : "music"

    tracks = Instagram::AudioService.new(@planned_post.user)
      .search(audio_type: audio_type, query: params[:q])

    render json: { tracks: tracks.map { |track| audio_track_json(track) } }
  rescue Instagram::Error => e
    # A missing/expired token or an unconnected account surfaces here — the
    # picker shows the message rather than silently returning no results.
    render json: { error: e.message }, status: :bad_gateway
  end

  # JSON — powers the collaborator typeahead on the edit form.
  # Instagram has no username search endpoint, so suggestions come from the
  # usernames this user has collaborated with before.
  def collaborator_search
    render json: {
      collaborators: PlannedPost.collaborator_suggestions(@planned_post.user, query: params[:q])
    }
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
    payload = @planned_post.platform_payload || {}

    case post_type
    when "carousel"
      if carousel_ids.size < 2
        @planned_post.errors.add(:base, "Carousel posts require at least 2 media assets")
        load_form_data
        render :edit, status: :unprocessable_entity
        return
      end
      @planned_post.media_asset_id = carousel_ids.first
      @planned_post.platform_payload = payload.except("post_type").merge("carousel_asset_ids" => carousel_ids)
    when "story"
      # Caption, hashtags, collaborators and audio are left on the record even
      # though Instagram's Stories API accepts none of them: the form still
      # submits them, and keeping them means switching back to a feed post does
      # not silently lose the text. Instagram::StoriesPublisher never reads them.
      @planned_post.platform_payload = payload.except("carousel_asset_ids").merge("post_type" => "story")
    else
      @planned_post.platform_payload = payload.except("carousel_asset_ids", "post_type")
    end

    if @planned_post.instagram?
      begin
        apply_instagram_options!
      rescue ArgumentError => e
        @planned_post.errors.add(:base, e.message)
        load_form_data
        render :edit, status: :unprocessable_entity
        return
      end
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

  def platform_name
    helpers.platform_display_name(@planned_post.platform)
  end

  def load_form_data
    @media_assets = MediaAsset.where(status: [ :discovered, :processed ]).order(:external_name)
    @social_templates = SocialTemplate.order(:name)
    @carousel_asset_ids = @planned_post.platform_payload&.dig("carousel_asset_ids") || []
    @collaborators = @planned_post.platform_payload&.dig("collaborators") || []
    @selected_audio = selected_audio_for(@planned_post)
  end

  # The currently attached track, as the audio picker renders it.
  # Title/artist are stored alongside the ID purely so the form and show page
  # can name the track without a round-trip to Meta.
  def selected_audio_for(planned_post)
    payload = planned_post.platform_payload.to_h
    return nil if payload["audio_id"].blank?

    {
      "audio_id" => payload["audio_id"],
      "title"    => payload["audio_title"],
      "artist"   => payload["audio_artist"]
    }
  end

  # Merge the Instagram-only options (collaborators, attached audio) from the
  # form into platform_payload.
  #
  # Collaborators are normalized by the same code the publisher uses, so the
  # form rejects a 4th collaborator instead of failing at publish time.
  def apply_instagram_options!
    payload = @planned_post.platform_payload.to_h

    collaborators = Instagram::PublishOptions.normalize_collaborators(
      params.dig(:planned_post, :collaborators)
    )

    payload = collaborators.any? ? payload.merge("collaborators" => collaborators) : payload.except("collaborators")

    audio_id = params.dig(:planned_post, :audio_id).presence

    payload =
      if audio_id
        payload.merge(
          "audio_id"     => audio_id,
          "audio_title"  => params.dig(:planned_post, :audio_title).presence,
          "audio_artist" => params.dig(:planned_post, :audio_artist).presence
        ).compact
      else
        payload.except("audio_id", "audio_title", "audio_artist")
      end

    @planned_post.platform_payload = payload
  end

  # Compact JSON shape for one track from the Instagram Audio API.
  def audio_track_json(track)
    {
      audio_id:   track["audio_id"],
      title:      track["title"],
      artist:     track["display_artist"] || track["ig_username"],
      audio_type: track["audio_type"],
      duration:   format_duration(track["duration_in_ms"]),
      thumbnail:  track["cover_artwork_thumbnail_uri"] || track["profile_picture_url"]
    }
  end

  def format_duration(milliseconds)
    return nil if milliseconds.blank?

    total_seconds = milliseconds.to_i / 1000
    format("%d:%02d", total_seconds / 60, total_seconds % 60)
  end

  def planned_post_params
    params.require(:planned_post).permit(:caption, :hashtags, :scheduled_at, :status, :media_asset_id, :social_template_id)
  end
end
