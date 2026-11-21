# POST /episodes/:episode_id/translation_requests { pair } — "I want this story in …" under a user story (7.8): one vote
# per reader, counted in the admin; when the translation exists, the reader goes straight to it.
class TranslationRequestsController < ApplicationController
  include ReaderIdentity
  include StoriesHelper

  allow_unauthenticated_access
  rate_limit to: 20, within: 1.minute

  def create
    episode = Episode.find(params[:episode_id])
    pair = LanguagePair.active.find_by(code: params[:pair])
    # The button is under the story, so whoever presses it holds the link.
    return head(:not_found) unless pair && episode.user_story? && StoryAccess.new(episode, current_reader, via_link: true).readable?

    translated = Stories::Translation.existing(episode, pair)
    return redirect_to(read_path(translated)) if translated && StoryAccess.new(translated, current_reader, via_link: true).readable?

    vote = current_reader.translation_requests.find_or_create_by!(episode:, language_pair: pair)
    track("translation_requested", user: current_reader, episode:, pair: pair.code) if vote.previously_new_record?
    redirect_to read_path(episode), notice: t("stories.translation.thanks", pair: pair_label(pair))
  rescue ActiveRecord::RecordNotUnique
    redirect_to read_path(episode)
  end
end
