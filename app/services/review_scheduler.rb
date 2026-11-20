# FSRS v6 (fsrs_ruby) for saved words. A UserWord stores the full card state; answering a card
# moves it to its next due time and logs the answer in WordReview.
class ReviewScheduler
  RATINGS = { "again" => FsrsRuby::Rating::AGAIN, "hard" => FsrsRuby::Rating::HARD,
              "good" => FsrsRuby::Rating::GOOD, "easy" => FsrsRuby::Rating::EASY }.freeze
  CARD_FIELDS = %i[due stability difficulty elapsed_days scheduled_days learning_steps reps lapses state last_review].freeze

  # Cards in learning are shown again within the same session if due this soon (like Anki's learn-ahead).
  LEARN_AHEAD = 20.minutes

  def self.fsrs
    @fsrs ||= FsrsRuby.new(
      request_retention: 0.9,
      maximum_interval: 365,
      enable_short_term: true,
      learning_steps: %w[1m 10m],
      relearning_steps: %w[10m],
      # Fuzz spreads due dates randomly; preview and answer would then disagree with the label on
      # the button. Worth turning on once people have hundreds of cards piling up on the same day.
      enable_fuzz: false
    )
  end

  def initialize(user_word, now: Time.current)
    @user_word = user_word
    @now = now
  end

  # { "again" => 60, "hard" => 360, "good" => 600, "easy" => 691200 } — seconds until the card returns
  def intervals
    preview = self.class.fsrs.repeat(card, @now)
    RATINGS.transform_values { |grade| (preview[grade].card.due - @now).round }
  end

  def answer!(rating)
    grade = RATINGS.fetch(rating.to_s) { raise ArgumentError, "unknown rating #{rating.inspect}" }
    before = card
    after = self.class.fsrs.next(before, @now, grade).card

    UserWord.transaction do
      @user_word.update!(after.to_h.slice(*CARD_FIELDS).merge(last_review: @now))
      @user_word.word_reviews.create!(
        user: @user_word.user, rating: grade, state: before.state,
        elapsed_days: after.elapsed_days, scheduled_days: after.scheduled_days,
        due_before: before.due, due_after: after.due, reviewed_at: @now
      )
    end
    @user_word
  end

  private
    def card
      FsrsRuby::Card.new(**@user_word.attributes.symbolize_keys.slice(*CARD_FIELDS))
    end
end
