module Admin
  class ImportsController < BaseController
    def new
    end

    def create
      json = params[:file].presence&.read || params[:json].to_s
      return redirect_to(new_admin_import_path, alert: "Загрузите файл или вставьте JSON") if json.blank?

      episode = Episodes::Importer.call(json, status: params[:publish] == "1" ? "published" : "review")
      redirect_to admin_episode_path(episode), notice: "Импортировано: #{episode.panels.size} кадров, #{episode.tokens.count} токенов"
    rescue Episodes::Importer::Invalid => e
      @errors = e.details
      @json = json
      render :new, status: :unprocessable_entity
    end
  end
end
