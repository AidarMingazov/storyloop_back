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

  # #check(text, episode: nil) → Stories::Verdict
  def moderator
    MODERATORS.fetch(config.moderator).constantize.new
  end

  def free_generations = config.free_generations
  def reports_to_hide = config.reports_to_hide

  # Rule categories a story can break (moderation, 7.6); the status page names the category.
  REJECTIONS = %w[sexual violence hate self_harm personal copyright illegal minors images other].freeze

  # Raised by a generator or the job when the story must not be made (moderation).
  class Rejected < StandardError
    attr_reader :category

    def initialize(message = nil, category: "other")
      @category = REJECTIONS.include?(category.to_s) ? category.to_s : "other"
      super(message)
    end
  end

  # #check(text, episode: nil) of a moderator → Verdict
  Verdict = Data.define(:ok, :reason, :category) do
    def self.ok = new(ok: true, reason: nil, category: nil)
    def self.rejected(reason, category: "other") = new(ok: false, reason:, category:)
    def ok? = ok
    def raise_if_rejected! = ok? || raise(Rejected.new(reason, category:))
  end
end
