# User stories (wave 7): configuration and the two seams the AI pipeline (wave 6) plugs into.
module Stories
  GENERATORS = { "fake" => "Stories::FakeGenerator", "pipeline" => "Ai::StoryPipeline" }.freeze
  MODERATORS = { "fake" => "Stories::FakeModerator", "pipeline" => "Ai::StoryModerator" }.freeze

  module_function

  def config = Rails.configuration.x.stories

  # See Stories::Generator for the contract.
  def generator
    GENERATORS.fetch(config.generator).constantize.new
  end

  # #check(text) → Stories::Verdict
  def moderator
    MODERATORS.fetch(config.moderator).constantize.new
  end

  def free_generations = config.free_generations
  def reports_to_hide = config.reports_to_hide

  # Raised by a generator or the job when the story must not be made (moderation, limits).
  class Rejected < StandardError; end

  Verdict = Data.define(:ok, :reason) do
    def self.ok = new(ok: true, reason: nil)
    def self.rejected(reason) = new(ok: false, reason: reason)
    def ok? = ok
  end
end
