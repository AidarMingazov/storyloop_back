# Admin "Generate episode" form and bin/rails ai:generate: the whole pipeline for a new episode (3–5 min).
class GenerateEpisodeJob < ApplicationJob
  queue_as :ai

  discard_on ActiveJob::DeserializationError

  # options: number, format, panels, brief, target_words
  def perform(series, options = {})
    Ai::Pipeline.generate(series, **options.symbolize_keys.slice(:number, :format, :panels, :brief, :target_words))
  end
end
