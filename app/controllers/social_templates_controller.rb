# frozen_string_literal: true

class SocialTemplatesController < ApplicationController
  before_action :set_social_template, only: %i[show edit update destroy]

  def index
    @social_templates = SocialTemplate.includes(:user).order(created_at: :desc)
  end

  def show
  end

  def new
    @social_template = SocialTemplate.new
  end

  def create
    @social_template = SocialTemplate.new(social_template_params)
    @social_template.user = Current.user

    if @social_template.save
      redirect_to @social_template, notice: "Social template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
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

  def destroy
    @social_template.destroy
    redirect_to social_templates_path, notice: "Social template was successfully deleted."
  end

  private

  def set_social_template
    @social_template = SocialTemplate.find(params[:id])
  end

  def social_template_params
    params.require(:social_template).permit(:name, :platform, :default_caption, :max_caption_length, :recommended_aspect_ratio)
  end
end
