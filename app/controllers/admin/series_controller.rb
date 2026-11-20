module Admin
  class SeriesController < BaseController
    before_action :set_series, only: %i[show edit update destroy]

    def index
      @series = Series.includes(:language_pair, :episodes).order(:language_pair_id, :position, :id)
    end

    def show
      @episodes = @series.episodes.includes(:panels)
    end

    def new
      @series = Series.new(language_pair: LanguagePair.first, cefr_level: "A2")
    end

    def create
      @series = Series.new(series_params)
      if @series.save
        redirect_to admin_series_path(@series), notice: "Серия создана"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @series.update(series_params)
        redirect_to admin_series_path(@series), notice: "Серия сохранена"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @series.destroy!
      redirect_to admin_series_index_path, notice: "Серия удалена", status: :see_other
    end

    private
      def set_series
        @series = Series.find(params[:id])
      end

      def series_params
        params.expect(series: %i[language_pair_id slug title description genre cefr_level style_prompt status position cover])
      end
  end
end
