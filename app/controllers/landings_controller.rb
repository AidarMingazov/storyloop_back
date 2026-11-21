# Ad landing per pair (/en-ru, /ko-en), written in the learner's native language.
class LandingsController < ApplicationController
  allow_unauthenticated_access

  def show
    @pair = LanguagePair.active.find_by!(code: params[:pair])
    I18n.locale = @pair.ui_locale
    track("landing_viewed", user: resume_session&.user, landing: @pair.code,
                            pair: @pair.code, referrer: request.referer.presence)
  end
end
