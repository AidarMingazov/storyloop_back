module Admin
  class EpisodesController < BaseController
    before_action :set_episode, only: %i[show edit update destroy publish unpublish]

    def show
      @panels = @episode.panels.includes(image_attachment: :blob, bubbles: [ :character, { tokens: :lexeme } ])
    end

    def new
      @series = Series.find(params[:series_id])
      @episode = @series.episodes.build(number: (@series.episodes.maximum(:number) || 0) + 1,
                                        cefr_level: @series.cefr_level, format: "webtoon")
    end

    def create
      @series = Series.find(params[:series_id])
      @episode = @series.episodes.build(episode_params)
      if @episode.save
        redirect_to admin_episode_path(@episode), notice: "Эпизод создан"
      else
        @series = @episode.series
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @episode.update(episode_params)
        redirect_to admin_episode_path(@episode), notice: "Эпизод сохранён"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @episode.destroy!
      redirect_to admin_series_path(@episode.series), notice: "Эпизод удалён", status: :see_other
    end

    def publish
      @episode.publish!
      redirect_to admin_episode_path(@episode), notice: "Эпизод опубликован"
    end

    def unpublish
      @episode.review!
      redirect_to admin_episode_path(@episode), notice: "Эпизод снят с публикации и вернулся на проверку"
    end

    private
      def set_episode
        @episode = Episode.find(params[:id])
      end

      def episode_params
        params.expect(episode: [ :number, :title, :format, :cefr_level, :status, :free, :estimated_minutes, :synopsis,
                                :target_words_text ]).tap do |attrs|
          if (words = attrs.delete(:target_words_text))
            attrs[:target_words] = words.split(/[,\n]/).map(&:strip).compact_blank
          end
        end
      end
  end
end
