class ReviewsController < ApplicationController
  include ReaderIdentity
  include ReaderLocale

  allow_unauthenticated_access

  def show
    @reader = resume_session&.user
    return unless @reader

    queue = @reader.user_words.review_queue
    @remaining = queue.count
    @word = queue.includes(lexeme: [], source_token: { bubble: { panel: { episode: { series: :language_pair } } } }).first
    @intervals = ReviewScheduler.new(@word).intervals if @word
    @reviewed_today = @reader.word_reviews.on_day.count
    @next_due = @reader.user_words.minimum(:due) unless @word
  end

  # POST /review/answer  { user_word_id, rating: again|hard|good|easy }
  def answer
    word = current_reader.user_words.find(params.expect(:user_word_id))
    ReviewScheduler.new(word).answer!(params.expect(:rating))
    redirect_to review_path, status: :see_other
  rescue ArgumentError
    head :unprocessable_entity
  end
end
