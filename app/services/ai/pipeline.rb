module Ai
  # Episode generation: script → images → layout → tokens → audio (docs/ai-pipeline-research.md §7).
  # The episode is "generating" while steps run and "review" when they are done; a published episode keeps its status.
  # A failed step stops the run (the episode goes back to draft) — its GenerationLog has the error. Panels or
  # recordings that failed inside a step do not stop it: they are listed on the review screen.
  #
  #   Ai::Pipeline.generate(series, format: "webtoon", brief: "…")  # new episode, all steps
  #   Ai::Pipeline.rerun(episode, "tokens")                        # tokens again, then audio for new words
  module Pipeline
    STEPS = %w[script scene images layout tokens audio].freeze
    # Steps that have to run again after a step is redone.
    THEN = { "script" => %w[scene images layout tokens audio], "tokens" => %w[audio] }.freeze
    # The episode reads fine without them: a failure is logged (GenerationLog) and the run goes on.
    OPTIONAL = %w[scene].freeze

    module_function

    def generate(series, **script_options)
      episode = Steps::Script.call(series, **script_options)
      run(episode, THEN.fetch("script"))
    end

    # Redo one step on the whole episode (force: redraw, re-place, re-record what exists), then its dependents.
    # bubbles: limits the tokens step to these bubbles.
    def rerun(episode, step, bubbles: nil)
      raise ArgumentError, "unknown step #{step.inspect}" unless STEPS.include?(step.to_s)

      step = step.to_s
      if step == "script"
        options = episode.generation_logs.where(step: "script").order(:id).last&.metadata.to_h
        episode = Steps::Script.call(episode.series, number: episode.number, format: episode.format,
                                                     panels: options["panels"], brief: options["brief"],
                                                     target_words: options["requested_words"])
        return run(episode, THEN.fetch("script"))
      end

      run(episode, [ step ] + THEN.fetch(step, []), force: [ step ], bubbles:)
    end

    def run(episode, steps, force: [], bubbles: nil)
      published = episode.published?
      episode.update!(status: :generating) unless published
      steps.each { |step| run_step(episode, step, force: force.include?(step), bubbles:) }
      episode.update!(status: :review) unless published
      episode
    rescue StandardError
      episode.update_columns(status: "draft") if episode&.persisted? && !published
      raise
    end

    def run_step(episode, step, force:, bubbles:)
      case step
      when "scene" then Steps::Scene.call(episode, force:)
      when "images" then Steps::Images.call(episode, panels: (episode.panels.to_a if force))
      when "layout" then Steps::Layout.call(episode, force:)
      when "tokens" then Steps::Tokens.call(episode, bubbles:)
      when "audio" then Steps::Audio.call(episode, force: force && bubbles.nil?)
      end
    rescue Ai::Error => e
      raise unless OPTIONAL.include?(step)

      Rails.logger.warn("[ai] optional step #{step} of episode #{episode.id} failed, going on: #{e.class}: #{e.message.truncate(200)}")
    end
  end
end
