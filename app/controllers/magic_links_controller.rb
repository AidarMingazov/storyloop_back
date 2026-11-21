# Passwordless sign-in and sign-up. Existing accounts get a one-time sign-in link; a guest gets a
# link that turns them into a registered user with that email when they open it.
class MagicLinksController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create, with: -> { redirect_to new_magic_link_path, alert: t("auth.rate_limited") }

  SIGNUP_PURPOSE = :magic_signup

  def new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    return redirect_to(new_magic_link_path, alert: t("auth.magic_link.invalid_email")) unless email.match?(URI::MailTo::EMAIL_REGEXP)

    token = if (user = User.registered.find_by(email_address: email))
      user.generate_token_for(:magic_login)
    else
      signup_verifier.generate({ "user_id" => current_reader.id, "email" => email }, expires_in: 20.minutes)
    end
    MagicLinkMailer.with(email: email, url: magic_link_url(token: token), locale: I18n.locale.to_s).sign_in.deliver_later

    redirect_to new_magic_link_path(sent: email)
  end

  # GET /magic_link?token=…
  def show
    if (user = User.registered.find_by_token_for(:magic_login, params[:token].to_s))
      user.update!(magic_login_at: Time.current) # burns the link
      sign_in_keeping_guest_progress(user)
      redirect_to root_path, notice: t("auth.magic_link.signed_in")
    elsif (payload = signup_verifier.verified(params[:token].to_s))
      complete_signup(payload)
    else
      redirect_to new_magic_link_path, alert: t("auth.magic_link.expired")
    end
  end

  private
    def signup_verifier
      Rails.application.message_verifier(SIGNUP_PURPOSE)
    end

    def complete_signup(payload)
      email = payload["email"]
      if (existing = User.registered.find_by(email_address: email))
        sign_in_keeping_guest_progress(existing) # someone registered this email meanwhile
      else
        guest = User.find_by(id: payload["user_id"], guest: true) || User.new(guest: true)
        guest.register(email_address: email) or return redirect_to(new_magic_link_path, alert: t("auth.magic_link.expired"))
        track("signup", user: guest, method: "magic_link")
        sign_in_keeping_guest_progress(guest)
      end
      redirect_to root_path, notice: t("auth.registration.welcome")
    end
end
