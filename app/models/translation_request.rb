# "I want this story in my language" (7.8): a reader's vote for a translation of an episode into another pair.
# The admin sees the votes next to the story and starts the translation (TranslateEpisodeJob).
class TranslationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :episode
  belongs_to :language_pair

  validates :episode_id, uniqueness: { scope: %i[user_id language_pair_id] }
  validate :other_pair

  private
    def other_pair
      errors.add(:language_pair, :invalid) if episode && episode.series.language_pair_id == language_pair_id
    end
end
