class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :user_words, dependent: :destroy
  has_many :saved_lexemes, through: :user_words, source: :lexeme
  has_many :reading_progresses, dependent: :destroy
  has_many :word_reviews, dependent: :delete_all
  belongs_to :language_pair, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :guest?
  validates :password, presence: true, length: { minimum: 8 }, on: :create, unless: :guest?
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :password, confirmation: true, allow_blank: true
  validates :self_level, inclusion: { in: Cefr::LEVELS }, allow_nil: true

  scope :registered, -> { where(guest: false) }

  # Free episodes are open to everyone; paid ones need a subscription (wave 4 paywall, wave 7 Stripe).
  def can_read?(episode)
    admin? || episode.free?
  end

  # Interface language: the learner's pair, else the pair of the episode they read last.
  def ui_locale
    pair = language_pair || reading_progresses.order(updated_at: :desc).first&.episode&.series&.language_pair
    pair&.ui_locale
  end

  def saved?(lexeme)
    user_words.exists?(lexeme_id: lexeme.id)
  end
end
