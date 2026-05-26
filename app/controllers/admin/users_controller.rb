class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: %i[show edit update destroy invite update_password]

  def index
    @users = User.order(created_at: :desc)
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.password = SecureRandom.hex(24)

    if @user.save
      InviteMailer.invite(@user).deliver_later
      redirect_to admin_user_path(@user), notice: "User created and invite sent to #{@user.email_address}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == Current.user
      redirect_to admin_users_path, alert: "You cannot delete your own account."
    else
      @user.destroy!
      redirect_to admin_users_path, notice: "User deleted."
    end
  end

  def invite
    InviteMailer.invite(@user).deliver_later
    redirect_to admin_user_path(@user), notice: "Invite sent to #{@user.email_address}."
  end

  def update_password
    if @user.update(password_params)
      @user.sessions.destroy_all
      redirect_to admin_user_path(@user), notice: "Password updated. All sessions invalidated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    # brakeman:ignore:MassAssignment - admin-only controller; admins may promote/demote other users
    params.require(:user).permit(:name, :email_address, :admin)
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
