# Admin "Generate episodes" form and bin/rails ai:generate: the whole pipeline for count new episodes, one after
# another (each next script remembers the previous synopses), 3–5 min each. brief and target_words apply to the first.
class GenerateEpisodeJob < ApplicationJob
  queue_as :ai

  discard_on ActiveJob::DeserializationError

  # options: count, format, panels, brief, target_words
  def perform(series, options = {})
    options = options.symbolize_keys
    first = options.slice(:format, :panels, :brief, :target_words)
    Integer(options.fetch(:count, 1)).times.map do |index|
      Ai::Pipeline.generate(series, **(index.zero? ? first : first.slice(:format, :panels)))
    end
  end
end
