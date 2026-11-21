class UserWord < ApplicationRecord
  belongs_to :user
  belongs_to :lexeme
  belongs_to :source_token, class_name: "Token", optional: true
  has_many :word_reviews, dependent: :delete_all

  validates :lexeme_id, uniqueness: { scope: :user_id }

  attribute :due, default: -> { Time.current }

  after_create_commit :count_save_on_episode

  scope :due_now, ->(at = Time.current) { where(due: ..at) }
  # What the review screen shows next: everything due, plus learning cards coming back within minutes.
  scope :review_queue, ->(at = Time.current) { where(due: ..(at + ReviewScheduler::LEARN_AHEAD)).order(:due, :id) }
  scope :due_today, ->(at = Time.current) { where(due: ..at.end_of_day) }

  # The pair the word was learned in: from the episode it came from, or by the word's language.
  def language_pair
    source_token&.bubble&.panel&.episode&.series&.language_pair ||
      LanguagePair.find_by(target_lang: lexeme.language)
  end

  def new_card? = state.zero?

  private
    # Saved words feed the "popular" sort of the community feed (7.7).
    def count_save_on_episode
      episode_id = source_token&.bubble&.panel&.episode_id
      Episode.update_counters(episode_id, saves_count: 1) if episode_id
    end
end
