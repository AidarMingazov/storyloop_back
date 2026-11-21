# "Hide author" (7.6): the user no longer sees this author's stories in the feed or on author pages.
class AuthorBlock < ApplicationRecord
  belongs_to :user
  belongs_to :author, class_name: "User"

  validates :author_id, uniqueness: { scope: :user_id }
  validate :not_self

  private
    def not_self
      errors.add(:author, :invalid) if author_id == user_id
    end
end
