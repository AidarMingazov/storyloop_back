# One pipeline step run (or a retry of it) with everything the AI calls inside it cost.
#
#   GenerationLog.track(step: "script", episode:) do
#     Ai.llm(:script).chat(messages, json: true)   # tokens and cost are added to the log automatically
#   end
#
# Several calls in one block (retries with error feedback, one image per panel) add up. A raised error marks the
# log failed and is re-raised.
class GenerationLog < ApplicationRecord
  STEPS = %w[script images layout tokens audio vision sheets stt markup_comparison moderation].freeze

  belongs_to :episode, optional: true

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, default: :running, validate: true

  validates :step, inclusion: { in: STEPS }

  scope :for_character, ->(character) { where("metadata->>'character_id' = ?", character.id.to_s) }

  def self.track(step:, episode: nil, metadata: {})
    log = create!(step: step.to_s, episode:, metadata:)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    succeeded = false
    result = Ai.with_log(log) { yield log }
    succeeded = true
    result
  ensure
    # $! is the error that is propagating (also interrupts and job timeouts)
    log&.finish!(succeeded ? :succeeded : :failed, started, error: (succeeded ? nil : $!))
  end

  # Called by the Ai adapters (Ai.record) for every finished call inside track.
  def add_call(result)
    usage = result.usage
    self.provider = result.provider
    self.model = result.model
    self.input_tokens += usage.input_tokens
    self.output_tokens += usage.output_tokens
    self.images += usage.images
    self.characters += usage.characters
    self.cost_usd += result.cost_usd.to_d
    self.metadata = metadata.merge(
      "calls" => metadata.fetch("calls", 0) + 1,
      "reasoning_tokens" => metadata.fetch("reasoning_tokens", 0) + usage.reasoning_tokens,
      "cached_tokens" => metadata.fetch("cached_tokens", 0) + usage.cached_tokens
    )
    save!
  end

  def finish!(status, started, error: nil)
    attributes = { status:, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round }
    attributes[:error] = "#{error.class}: #{error.message}".truncate(2_000) if error
    update!(attributes)
  end
end
