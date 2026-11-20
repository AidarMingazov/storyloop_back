module Admin
  class LexemesController < BaseController
    before_action :set_lexeme, only: %i[edit update]

    def index
      @language = params[:language].presence
      @query = params[:q].to_s.strip
      scope = Lexeme.order(:language, :lemma)
      scope = scope.where(language: @language) if @language
      scope = scope.where("lemma ILIKE ?", "%#{Lexeme.sanitize_sql_like(@query)}%") if @query.present?
      @total = scope.count
      @lexemes = scope.left_joins(:tokens).group(:id).select("lexemes.*, COUNT(tokens.id) AS tokens_count").limit(200)
    end

    def edit
    end

    def update
      attrs = params.expect(lexeme: [ :lemma, :pos, :cefr_level, :romanization, translations: {} ])
      attrs[:translations] = @lexeme.translations.merge(attrs[:translations].to_h) if attrs[:translations]
      if @lexeme.update(attrs)
        redirect_to admin_lexemes_path(language: @lexeme.language, q: @lexeme.lemma), notice: "Лексема сохранена"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_lexeme
        @lexeme = Lexeme.find(params[:id])
      end
  end
end
