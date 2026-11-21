class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: t("auth.rate_limited") }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t("auth.password.sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("auth.password.updated")
    else
      alert = @user.errors.of_kind?(:password_confirmation, :confirmation) ? t("auth.password.mismatch") : t("auth.password.too_short")
      redirect_to edit_password_path(params[:token]), alert: alert
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("auth.password.invalid_link")
    end
end
