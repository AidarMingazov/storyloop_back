module Admin
  class CharactersController < BaseController
    before_action :set_character, only: %i[edit update destroy generate_sheet]

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
      @sheet_log = GenerationLog.where(step: "sheets").for_character(@character).order(:id).last
    end

    def update
      if @character.update(character_params)
        redirect_to admin_series_path(@character.series), notice: "Персонаж сохранён"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def generate_sheet
      if @character.appearance_prompt.blank?
        redirect_to edit_admin_character_path(@character), alert: "Сначала заполните внешность персонажа"
      else
        GenerateCharacterSheetJob.perform_later(@character)
        redirect_to edit_admin_character_path(@character), notice: "Лист генерируется (~30 с), обновите страницу"
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
        params.expect(character: [ :key, :name, :appearance_prompt, :protagonist, :voice, :speech_level, :avatar, :sheet,
                                       reference_images: [] ])
      end
  end
end
