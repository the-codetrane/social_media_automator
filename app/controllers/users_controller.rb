# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update]

  def index
    @users = User.order(created_at: :desc)
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email_address)
  end
end
