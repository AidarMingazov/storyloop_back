class MagicLinkMailer < ApplicationMailer
  def sign_in
    @url = params[:url]
    I18n.with_locale(params[:locale] || I18n.default_locale) do
      mail to: params[:email], subject: t("auth.magic_link.email_subject")
    end
  end
end
