module Api
  module V1
    class UserWordsController < BaseController
      before_action :require_user!

      # GET /api/v1/user_words → saved words with their review state
      def index
        words = current_user.user_words.includes(:lexeme).order(created_at: :desc)
        render json: words.map { |w| { lexeme_id: w.lexeme_id, lemma: w.lexeme.lemma, due: w.due, state: w.state } }
      end

      # POST /api/v1/user_words  { lexeme_id, token_id? } → 201
      def create
        lexeme = Lexeme.find(params.expect(:lexeme_id))
        token = lexeme.tokens.find_by(id: params[:token_id])
        word = current_user.user_words.find_or_create_by!(lexeme: lexeme) { |w| w.source_token = token }
        track("word_saved", episode: token&.bubble&.panel&.episode, lemma: lexeme.lemma) if word.previously_new_record?
        render json: { lexeme_id: lexeme.id, saved: true, due: word.due }, status: :created
      end

      # DELETE /api/v1/user_words/:lexeme_id
      def destroy
        current_user.user_words.where(lexeme_id: params[:lexeme_id]).destroy_all
        head :no_content
      end
    end
  end
end
