# Generates one user story in the background (7.3): the moderator checks the brief, the configured generator
# (fake or the AI pipeline, 7.4) makes the story, the moderator checks the result (7.6), and the request moves
# along — the status page follows over Turbo Streams. A rejected or failed story does not count toward the free
# limit. Lower priority than catalog work (Solid Queue runs lower numbers first).
#
# A comic from photos (7.11) runs twice: first the characters are drawn from the photos and the request waits for
# the author ("confirming"); StoriesController#confirm enqueues the job again for the story itself. The photos are
# deleted as soon as the request is finished, whatever the outcome.
class GenerateStoryJob < ApplicationJob
  queue_as :stories
  queue_with_priority 10
  discard_on ActiveJob::DeserializationError # the story was deleted meanwhile

  def perform(request)
    return if request.succeeded? || request.failed? || request.confirming?

    request.start!
    if request.prompt.present? && request.confirmed_at.nil?
      Stories.moderator.check(request.prompt, episode: request.episode, stage: "brief").raise_if_rejected!
    end
    if request.awaiting_confirmation?
      Stories.generator.cast_from_photos(request)
      return request.await_confirmation!
    end

    episode = Stories.generator.call(request)
    request.series.reload # the generator saved titles and status through its own records
    Stories.moderator.check(text_of(episode), episode:).raise_if_rejected!

    request.series.approved! if request.series.pending?
    request.succeed!
    track(request, "story_ready", seconds: request.duration&.round, cost_usd: episode.cost_usd.to_f)
    track(request, "story_published", listed: request.series.listed?) if request.series.visibility_public?
  rescue Stories::Rejected => e
    mark_failed(request, e, rejected: true)
  rescue StandardError => e
    Rails.error.report(e, context: { story_request_id: request.id })
    mark_failed(request, e, rejected: false)
  ensure
    request.purge_photos! if request.mode_photos? && (request.succeeded? || request.failed?)
  end

  private
    def mark_failed(request, error, rejected:)
      request.fail!(rejected ? error.message : "#{error.class}: #{error.message}", rejection: (error.category if rejected))
      track(request, "story_failed", rejected: rejected, category: (error.category if rejected))
    end

    def text_of(episode)
      episode.reload
      [ episode.series.title, episode.title, episode.synopsis, *episode.bubbles.pluck(:text, :translation).flatten ].compact.join("\n")
    end

    def track(request, event, **properties)
      Analytics.track(event, distinct_id: request.user.analytics_id,
                             properties: Analytics.context(user: request.user, episode: request.episode)
                                                  .merge(mode: request.mode, theme: request.theme, **properties))
    end
end
