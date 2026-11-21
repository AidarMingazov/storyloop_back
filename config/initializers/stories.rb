# User stories (wave 7). The generator and the moderator are swappable: "pipeline" is the AI pipeline
# (Stories::PipelineGenerator) and the AI classifier (Stories::AiModerator); "fake" needs no keys and costs nothing.
# Production uses the AI by default; development and tests the fakes (STORY_GENERATOR=pipeline to try it for real).
Rails.application.configure do
  ai_default = Rails.env.production? ? "pipeline" : "fake"
  config.x.stories.generator = ENV.fetch("STORY_GENERATOR", ai_default)
  config.x.stories.moderator = ENV.fetch("STORY_MODERATOR", ai_default)
  config.x.stories.free_generations = ENV.fetch("FREE_STORY_GENERATIONS", 3).to_i
  # Open reports that take a story out of the feed until a moderator looks at it.
  config.x.stories.reports_to_hide = ENV.fetch("STORY_REPORTS_TO_HIDE", 1).to_i
  # Fake generator: pause per step so the status screen can be seen in development.
  config.x.stories.fake_step_delay = ENV.fetch("FAKE_STORY_STEP_DELAY", Rails.env.development? ? 1.5 : 0).to_f
end
