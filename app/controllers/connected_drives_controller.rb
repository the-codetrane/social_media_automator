# frozen_string_literal: true

class ConnectedDrivesController < ApplicationController
  def index
    @connected_drives = ConnectedDrive.includes(:user).order(created_at: :desc)
  end
end
