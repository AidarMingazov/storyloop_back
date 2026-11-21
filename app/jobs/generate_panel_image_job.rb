# Redraw one panel (admin review screen). Failures are recorded in GenerationLog (step "images").
class GeneratePanelImageJob < ApplicationJob
  queue_as :ai

  retry_on Ai::RateLimited, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(panel)
    Ai::Steps::PanelImage.call(panel)
  end
end
