# frozen_string_literal: true

class SocialTemplatesController < ApplicationController
  def index
    @social_templates = SocialTemplate.includes(:user).order(created_at: :desc)
  end
end
