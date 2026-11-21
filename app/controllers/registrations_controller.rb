# Sign-up turns the current guest into a registered user (same record, so nothing to migrate).
class RegistrationsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: t("auth.rate_limited") }

  def new
    redirect_to root_path if authenticated? && !Current.user.guest?
  end

  def create
    reader = current_reader
    return redirect_to(root_path) unless reader.guest?

    if User.registered.exists?(email_address: params[:email_address].to_s.strip.downcase)
      return redirect_to new_session_path(email_address: params[:email_address]), alert: t("auth.registration.taken")
    end

    if reader.register(email_address: params[:email_address], password: params[:password].to_s)
      track("signup", user: reader, method: "password")
      redirect_to session.delete(:return_to_after_authenticating) || root_path, notice: t("auth.registration.welcome")
    else
      @errors = reader.errors.full_messages
      reader.reload
      render :new, status: :unprocessable_entity
    end
  end
end
