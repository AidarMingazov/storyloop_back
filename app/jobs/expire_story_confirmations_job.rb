# Comics from photos the author never confirmed (7.11): after a week the request fails (it stops counting toward
# the free limit) and the photos are deleted. Daily, config/recurring.yml.
class ExpireStoryConfirmationsJob < ApplicationJob
  queue_as :stories

  AFTER = 7.days

  def perform
    StoryRequest.confirming.where(updated_at: ...AFTER.ago).find_each do |request|
      request.fail!("not confirmed in #{AFTER.inspect}")
      request.purge_photos!
    end
  end
end
