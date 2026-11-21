# Confirmation screen of a comic from photos (7.11): draws one character's sheet again from the same photo.
# StoriesController#redraw marks the request busy (step "sheets"); the screen updates when the step is cleared.
class RedrawStorySheetJob < ApplicationJob
  queue_as :stories
  queue_with_priority 5 # the author is looking at the screen
  discard_on ActiveJob::DeserializationError

  def perform(request, character)
    return unless request.confirming?

    Stories.generator.redraw_sheet(request, character)
  rescue StandardError => e
    Rails.error.report(e, context: { story_request_id: request.id, character_id: character.id })
  ensure
    request.update!(step: nil) if request.confirming?
  end
end
