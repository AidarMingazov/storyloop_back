module Stories
  # The contract every story generator follows — Stories::FakeGenerator (seed episodes, no AI) and
  # Stories::PipelineGenerator (the wave 6 AI pipeline, 7.4). GenerateStoryJob calls `generator.call(request)`.
  #
  # Input — a StoryRequest:
  #   mode        theme | idea | text | surprise   (later photos, voice)
  #   theme       key of Stories::Themes (mode theme)
  #   cast_key    db/templates/ai/casts/<key>.yml the story is drawn with (picked on the form or by Stories::Cast.for)
  #   prompt      the idea (≤ 500 chars) or the learner's own text to adapt (≤ 3000 chars)
  #   language_pair, cefr_level, format (webtoon | chat)
  #   series      already created: author, visibility, slug, placeholder title
  #   episode     already created: number 1, status generating
  #   user, previous_requests — the author and their earlier briefs ("surprise me" should not repeat)
  #
  # It must:
  #   - fill request.episode (panels, bubbles, tokens, images, audio) inside request.series — e.g. by
  #     building episode JSON and passing it to Episodes::Importer with the series slug and number 1;
  #   - set real titles on the series and the episode, and `free: true`;
  #   - leave the episode `published` (no human review for user stories; StoryAccess still applies);
  #   - write GenerationLog rows with episode_id (cost of user generations, 7.5);
  #   - call request.progress!(step) when a step starts (StoryRequest::STEPS) — the status page shows it;
  #   - be safe to run again for the same request (job retries);
  #   - return the episode; raise to fail (Stories::Rejected for moderation) — the request becomes
  #     failed and does not count toward the free limit.
  module Generator
    def call(request)
      raise NotImplementedError
    end
  end
end
