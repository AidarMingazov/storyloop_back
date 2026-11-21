# Admin "Сравнение разметки": runs Ai::MarkupComparison for the chosen models (~1 min).
class CompareMarkupJob < ApplicationJob
  queue_as :ai

  discard_on ActiveJob::DeserializationError

  def perform(episode, models, id)
    Ai::MarkupComparison.run(id, episode, models)
  end
end
