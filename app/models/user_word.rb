class UserWord < ApplicationRecord
  belongs_to :user
  belongs_to :lexeme
  belongs_to :source_token, class_name: "Token", optional: true

  validates :lexeme_id, uniqueness: { scope: :user_id }

  attribute :due, default: -> { Time.current }

  scope :due_now, ->(at = Time.current) { where(due: ..at) }
end
