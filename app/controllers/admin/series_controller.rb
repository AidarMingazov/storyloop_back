module Admin
  class SeriesController < BaseController
    GENERATE_LIMIT = 5
    before_action :set_series, only: %i[show edit update destroy generate]

    def index
      @series = Series.catalog.includes(:language_pair, :episodes).order(:language_pair_id, :position, :id)
      @templates = Ai::SeriesTemplate.names
    end

    # db/templates/ai/series/<name>.yml → series, characters and their sheets (keeps sheets already attached).
    def load_template
      series = Ai::SeriesTemplate.load(params.expect(:name))
      redirect_to admin_series_path(series), notice: "Шаблон загружен"
    rescue ArgumentError, ActiveRecord::RecordNotFound => e
      redirect_to admin_series_index_path, alert: e.message
    end

    # The whole AI pipeline for N new episodes in the background.
    def generate
      options = params.expect(generation: %i[count format panels brief target_words])
      count = options[:count].to_i
      unless (1..GENERATE_LIMIT).cover?(count) && Episode::FORMATS.include?(options[:format])
        return redirect_to(admin_series_path(@series), alert: "Количество 1–#{GENERATE_LIMIT} и формат из списка")
      end

      GenerateEpisodeJob.perform_later(@series, {
        "count" => count, "format" => options[:format], "panels" => options[:panels].presence&.to_i,
        "brief" => options[:brief].presence, "target_words" => options[:target_words].to_s.split(",").map(&:strip).compact_blank
      }.compact)
      redirect_to admin_series_path(@series), notice: "Генерация запущена: #{count} эп., ~4 минуты на эпизод. Эпизоды появятся в списке"
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
        params.expect(series: %i[language_pair_id slug title description genre cefr_level tone art_style style_prompt
                                 narrator_voice status position cover])
      end
  end
end
