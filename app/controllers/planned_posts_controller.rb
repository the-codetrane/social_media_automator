# frozen_string_literal: true

class PlannedPostsController < ApplicationController
  def index
    @planned_posts = PlannedPost.includes(:user, :media_asset, :social_template).order(created_at: :desc)
  end
end
