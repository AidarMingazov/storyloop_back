# User stories (wave 7): configuration and the two seams — the generator (fake, or the wave 6 AI pipeline) and the
# moderator (fake marker check, or the AI classifier).
module Stories
  GENERATORS = { "fake" => "Stories::FakeGenerator", "pipeline" => "Stories::PipelineGenerator" }.freeze
  MODERATORS = { "fake" => "Stories::FakeModerator", "pipeline" => "Stories::AiModerator" }.freeze

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
