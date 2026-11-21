module Admin
  class BubblesController < BaseController
    before_action :set_bubble

    def edit
    end

    def update
      attrs = params.expect(bubble: %i[kind character_id text translation box_json audio])
      box = parse_json_field(attrs.delete(:box_json))
      if box == :invalid
        @bubble.errors.add(:box, "не JSON")
        return render(:edit, status: :unprocessable_entity)
      end

      @bubble.assign_attributes(attrs.merge(box: box))
      if @bubble.save
        redirect_to admin_episode_path(@bubble.episode, anchor: dom_id(@bubble.panel)), notice: notice_after_save
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_bubble
        @bubble = Bubble.find(params[:id])
      end

      # Editing the text can break token offsets; say so instead of silently keeping bad tokens.
      def notice_after_save
        broken = @bubble.tokens.reject(&:valid?)
        return "Пузырь сохранён" if broken.empty?

        "Пузырь сохранён. Проверьте токены: #{broken.map(&:surface).join(", ")} больше не совпадают с текстом"
      end
  end
end
