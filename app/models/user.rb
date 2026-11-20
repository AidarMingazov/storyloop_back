class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :user_words, dependent: :destroy
  has_many :saved_lexemes, through: :user_words, source: :lexeme
  has_many :reading_progresses, dependent: :destroy
  belongs_to :language_pair, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :guest?
  validates :password, presence: true, length: { minimum: 8 }, on: :create, unless: :guest?
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :password, confirmation: true, allow_blank: true
  validates :self_level, inclusion: { in: Cefr::LEVELS }, allow_nil: true

  scope :registered, -> { where(guest: false) }
end
