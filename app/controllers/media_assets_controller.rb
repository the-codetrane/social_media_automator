# frozen_string_literal: true

class MediaAssetsController < ApplicationController
  before_action :set_media_asset, only: %i[show edit update archive unarchive]

  SORT_COLUMNS = %w[external_name media_type status file_size first_seen_at published_at created_at].freeze
  AVAILABILITY_FILTERS = (MediaAsset::AVAILABILITIES + %w[all]).freeze

  def index
    @query     = params[:q].to_s.strip
    @sort      = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "created_at"
    @direction = params[:direction] == "asc" ? "asc" : "desc"
    @availability = AVAILABILITY_FILTERS.include?(params[:availability]) ? params[:availability] : "available"

    scope = MediaAsset.with_availability(@availability)
    scope = scope.where("external_name LIKE ?", "%#{@query}%") if @query.length >= 3

    @pagy, @media_assets = pagy(scope.order(@sort => @direction))
    @reserved_ids = MediaAsset.reserved_ids
  end

  def show
    @posts_using = @media_asset.posts_using.order(Arel.sql("COALESCE(published_at, scheduled_at, created_at) DESC"))
    @reserved_ids = MediaAsset.reserved_ids
  end

  def archive
    @media_asset.archive!
    redirect_back_or_to @media_asset, notice: "#{@media_asset.display_name} archived."
  end

  def unarchive
    @media_asset.unarchive!
    redirect_back_or_to @media_asset, notice: "#{@media_asset.display_name} restored."
  end

  def bulk_archive
    count = MediaAsset.active.where(id: bulk_ids).update_all(archived_at: Time.current, updated_at: Time.current)
    redirect_back_or_to media_assets_path, notice: "#{count} #{"asset".pluralize(count)} archived."
  end

  def bulk_unarchive
    count = MediaAsset.archived.where(id: bulk_ids).update_all(archived_at: nil, updated_at: Time.current)
    redirect_back_or_to media_assets_path, notice: "#{count} #{"asset".pluralize(count)} restored."
  end

  # Upload form, rendered inside the modal on the index page.
  def new
    @folders = MediaAssetFolders.list
  end

  # Files have already been direct-uploaded to storage by the browser; this
  # turns the resulting blobs into MediaAsset records.
  def create
    blobs = Array(params.dig(:media_asset, :signed_ids)).filter_map { |id| ActiveStorage::Blob.find_signed(id) }

    if blobs.empty?
      @folders = MediaAssetFolders.list
      flash.now[:alert] = "Select at least one photo or video to upload."
      return render :new, status: :unprocessable_entity
    end

    assets = blobs.map { |blob| create_media_asset_from_blob(blob) }

    redirect_to media_assets_path, notice: "#{assets.size} #{"file".pluralize(assets.size)} uploaded."
  end

  def edit
  end

  def update
    if @media_asset.update(media_asset_params)
      redirect_to @media_asset, notice: "Media asset was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_media_asset
    @media_asset = MediaAsset.find(params[:id])
  end

  def bulk_ids
    Array(params[:ids]).map(&:to_i).reject(&:zero?)
  end

  def media_asset_params
    params.require(:media_asset).permit(:external_name, :status)
  end

  def create_media_asset_from_blob(blob)
    asset = MediaAsset.create!(
      external_id:   SecureRandom.uuid,
      external_name: blob.filename.to_s,
      media_type:    media_type_for(blob),
      status:        :processed,
      first_seen_at: Time.current,
      mime_type:     blob.content_type,
      file_size:     blob.byte_size
    )
    asset.file.attach(blob)
    PublicBlobAcl.apply(blob)
    AnalyzeMediaAssetJob.perform_later(asset.id)
    asset
  end

  def media_type_for(blob)
    return :video if blob.video?
    return :audio if blob.audio?

    :image
  end
end
