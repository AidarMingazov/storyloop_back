class ReadingProgress < ApplicationRecord
  belongs_to :user
  belongs_to :episode, counter_cache: :reads_count # reads feed the "popular" sort (7.7)

  validates :episode_id, uniqueness: { scope: :user_id }

  scope :completed, -> { where.not(completed_at: nil) }

  def completed? = completed_at.present?
end
