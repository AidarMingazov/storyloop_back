# Admin "Translate into …" (7.8): Stories::Translation makes the copy in the other pair. A user story is checked by
# the moderator and published like the original (same author and visibility); a catalog episode waits for review.
class TranslateEpisodeJob < ApplicationJob
  queue_as :ai
  discard_on ActiveJob::DeserializationError

  def perform(episode, pair_code)
    pair = LanguagePair.find_by!(code: pair_code)
    return if Stories::Translation.existing(episode, pair)

    translated = Stories::Translation.call(episode, pair)
    series = translated.series
    return translated.update!(status: :review) unless series.source_user?

    text = [ translated.title, translated.synopsis, *translated.bubbles.pluck(:text, :translation).flatten ].compact.join("\n")
    Stories.moderator.check(text, episode: translated).raise_if_rejected!
    translated.update!(status: :published)
    series.approved! if series.pending?
    series.published! if series.draft?
  end
end
