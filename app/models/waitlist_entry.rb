class WaitlistEntry < ApplicationRecord
  belongs_to :language_pair, optional: true
  belongs_to :user, optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
