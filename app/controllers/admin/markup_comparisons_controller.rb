module Admin
  # 6.10: the same bubbles marked up by several models side by side (choice of the markup model).
  class MarkupComparisonsController < BaseController
    def index
      @episodes = Episode.joins(:panels).distinct.includes(series: :language_pair).order(:series_id, :number)
      @models = Ai.config.comparison_models
      @recent = Ai::MarkupComparison.recent
    end

    def create
      episode = Episode.find(params.expect(:episode_id))
      models = Array(params[:models]).compact_blank & Ai.config.comparison_models
      return redirect_to(admin_markup_comparisons_path, alert: "Выберите хотя бы одну модель") if models.empty?

      id = Ai::MarkupComparison.start(episode, models)
      redirect_to admin_markup_comparison_path(id), notice: "Сравнение запущено, ~1 минута"
    end

    def show
      @logs = Ai::MarkupComparison.logs(params[:id]).to_a
      raise ActiveRecord::RecordNotFound if @logs.empty?

      @episode = Episode.find(@logs.first.metadata["episode_id"])
      @bubbles = Ai::MarkupComparison.bubbles(@episode)
    end
  end
end
