module Admin
  class CharactersController < BaseController
    before_action :set_character, only: %i[edit update destroy]

    def new
      @series = Series.find(params[:series_id])
      @character = @series.characters.build
    end

    def create
      @series = Series.find(params[:series_id])
      @character = @series.characters.build(character_params)
      if @character.save
        redirect_to admin_series_path(@series), notice: "Персонаж добавлен"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @character.update(character_params)
        redirect_to admin_series_path(@character.series), notice: "Персонаж сохранён"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @character.destroy!
      redirect_to admin_series_path(@character.series), notice: "Персонаж удалён", status: :see_other
    end

    private
      def set_character
        @character = Character.find(params[:id])
      end

      def character_params
        params.expect(character: [ :key, :name, :appearance_prompt, :protagonist, :voice, :avatar, reference_images: [] ])
      end
  end
end
