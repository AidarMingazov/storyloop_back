# Generates one user story in the background (7.3): runs the configured generator (fake today, the AI
# pipeline after wave 6), checks the result with the moderator, and moves the request along — the
# status page follows over Turbo Streams. Lower priority than catalog work (Solid Queue runs lower
# numbers first).
class GenerateStoryJob < ApplicationJob
  queue_as :stories
  queue_with_priority 10
  discard_on ActiveJob::DeserializationError # the story was deleted meanwhile

  def perform(request)
    return if request.succeeded? || request.failed?

    request.start!
    episode = Stories.generator.call(request)
    request.series.reload # the generator saved titles and status through its own records
    verdict = Stories.moderator.check(text_of(episode))
    raise Stories::Rejected, verdict.reason unless verdict.ok?

    request.series.approved! if request.series.pending?
    request.succeed!
    track(request, "story_ready", seconds: request.duration&.round, cost_usd: episode.cost_usd.to_f)
    track(request, "story_published", listed: request.series.listed?) if request.series.visibility_public?
  rescue Stories::Rejected => e
    mark_failed(request, e, rejected: true)
  rescue StandardError => e
    Rails.error.report(e, context: { story_request_id: request.id })
    mark_failed(request, e, rejected: false)
  end

  private
    def mark_failed(request, error, rejected:)
      request.fail!(rejected ? error.message : "#{error.class}: #{error.message}")
      track(request, "story_failed", rejected: rejected)
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
