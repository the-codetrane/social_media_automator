# frozen_string_literal: true

class SocialTemplatesController < ApplicationController
  before_action :set_social_template, only: %i[show edit update]

  def index
    @social_templates = SocialTemplate.includes(:user).order(created_at: :desc)
  end

  def show
  end

  def edit
  end

  def update
    if @social_template.update(social_template_params)
      redirect_to @social_template, notice: "Social template was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_social_template
    @social_template = SocialTemplate.find(params[:id])
  end

  def social_template_params
    params.require(:social_template).permit(:name, :platform, :default_caption, :max_caption_length, :recommended_aspect_ratio)
  end
end
