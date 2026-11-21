class UserWordsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  # POST /user_words  { lexeme_id, token_id }
  def create
    lexeme = Lexeme.find(params.expect(:lexeme_id))
    token = lexeme.tokens.find_by(id: params[:token_id])
    word = current_reader.user_words.find_or_create_by!(lexeme: lexeme) { |w| w.source_token = token }
    if word.previously_new_record?
      track("word_saved", user: current_reader, episode: token&.bubble&.panel&.episode, lemma: lexeme.lemma)
    end

    render json: { lexeme_id: word.lexeme_id, saved: true }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render json: { lexeme_id: lexeme.id, saved: true }, status: :created
  end

  # DELETE /user_words/:lexeme_id
  def destroy
    current_reader.user_words.where(lexeme_id: params[:lexeme_id]).destroy_all
    render json: { lexeme_id: params[:lexeme_id].to_i, saved: false }
  end
end
