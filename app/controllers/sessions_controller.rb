class SessionsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("auth.rate_limited") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      sign_in_keeping_guest_progress(user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t("auth.session.invalid")
    end
  end

  def destroy
    terminate_session
    forget_visitor_id # the next visitor on this device starts a fresh analytics identity
    redirect_to new_session_path, status: :see_other
  end
end
