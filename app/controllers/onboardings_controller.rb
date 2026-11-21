# /start: pick a pair → pick a level → straight into the first episode, no sign-up.
class OnboardingsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  def show
    @pairs = LanguagePair.active.order(:code)
    @pair = @pairs.find_by(code: params[:pair])
    I18n.locale = @pair.ui_locale if @pair
  end

  def create
    pair = LanguagePair.active.find_by!(code: params.expect(:pair))
    level = Cefr::LEVELS.first(3).include?(params[:level]) ? params[:level] : "A1"

    reader = current_reader
    reader.update!(language_pair: pair, self_level: level, onboarded_at: Time.current)
    track("onboarding_completed", user: reader)

    episode = Library.first_episode_for(pair, level)
    redirect_to episode ? episode_path(episode) : root_path
  end
end
