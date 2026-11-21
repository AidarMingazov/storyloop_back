# Review screen: redo one pipeline step (and the steps that depend on it); bubble_ids limit the tokens step.
class RerunPipelineStepJob < ApplicationJob
  queue_as :ai

  discard_on ActiveJob::DeserializationError

  def perform(episode, step, bubble_ids = nil)
    bubbles = episode.bubbles.where(id: bubble_ids).includes(:panel, :character).to_a if bubble_ids
    Ai::Pipeline.rerun(episode, step, bubbles:)
  end
end
