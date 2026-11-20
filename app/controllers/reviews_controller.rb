class ReviewsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  # Placeholder until wave 3 (FSRS): lists saved words.
  def show
    @words = current_reader.user_words.includes(lexeme: [], source_token: :bubble).order(created_at: :desc)
  end
end
