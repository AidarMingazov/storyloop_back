class WordReview < ApplicationRecord
  belongs_to :user_word
  belongs_to :user

  validates :rating, inclusion: { in: 1..4 }

  scope :on_day, ->(time = Time.current) { where(reviewed_at: time.all_day) }
end
