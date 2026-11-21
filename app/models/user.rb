class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :user_words, dependent: :destroy
  has_many :saved_lexemes, through: :user_words, source: :lexeme
  has_many :reading_progresses, dependent: :destroy
  has_many :word_reviews, dependent: :delete_all
  belongs_to :language_pair, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Guests have neither email nor password. Registered users always have an email; the password is
  # optional because people may sign up and sign in with a magic link only.
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, unless: :guest?
  validates :password, presence: true, on: :registration
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :password, confirmation: true, allow_blank: true
  validates :self_level, inclusion: { in: Cefr::LEVELS }, allow_nil: true

  # Valid for 20 minutes and only until the next magic-link sign-in.
  generates_token_for :magic_login, expires_in: 20.minutes do
    [ email_address, magic_login_at&.to_i ]
  end

  scope :registered, -> { where(guest: false) }

  # Free episodes are open to everyone; paid ones need a subscription (wave 7 Stripe).
  def can_read?(episode)
    admin? || episode.free?
  end

  def saved?(lexeme)
    user_words.exists?(lexeme_id: lexeme.id)
  end

  # Interface language: the learner's pair, else the pair of the episode they read last.
  def ui_locale
    pair = language_pair || reading_progresses.order(updated_at: :desc).first&.episode&.series&.language_pair
    pair&.ui_locale
  end

  def onboarded? = onboarded_at.present? || language_pair_id.present?

  # Guest → registered on the same record: progress, words and analytics id stay.
  def register(email_address:, password: nil)
    assign_attributes(email_address: email_address, password: password.presence, guest: false)
    save(context: password.nil? ? nil : :registration)
  end

  # Moves a guest's words, reviews and reading progress into this account, then deletes the guest.
  def absorb_guest!(guest)
    return unless guest&.guest? && guest != self

    transaction do
      known = user_words.pluck(:lexeme_id)
      guest.user_words.where.not(lexeme_id: known).find_each do |word|
        word.update_columns(user_id: id)
        word.word_reviews.update_all(user_id: id)
      end

      guest.reading_progresses.each do |progress|
        mine = reading_progresses.find_by(episode_id: progress.episode_id)
        if mine
          mine.update!(last_panel_position: [ mine.last_panel_position, progress.last_panel_position ].max,
                       completed_at: mine.completed_at || progress.completed_at)
        else
          progress.update_columns(user_id: id)
        end
      end

      self.language_pair ||= guest.language_pair
      self.self_level ||= guest.self_level
      self.onboarded_at ||= guest.onboarded_at
      self.utm = guest.utm if utm.blank?
      save!
      guest.reload.destroy!
    end
  end
end
