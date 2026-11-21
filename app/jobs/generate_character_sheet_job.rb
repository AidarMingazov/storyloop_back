# Admin "Generate sheet" button. Failures are already recorded in GenerationLog (step "sheets").
class GenerateCharacterSheetJob < ApplicationJob
  queue_as :ai

  retry_on Ai::RateLimited, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(character)
    Ai::CharacterSheet.call(character)
  end
end
