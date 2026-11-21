module Admin
  class BubblesController < BaseController
    before_action :set_bubble

    def edit
    end

    def update
      attrs = params.expect(bubble: [ :kind, :character_id, :text, :translation, :audio, box: Bubble::BOX_KEYS ])
      @bubble.assign_attributes(attrs.except(:box))
      @bubble.box = box_from(attrs[:box]) if attrs.key?(:box)
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

      # Four percent fields; all empty = no box (the bubbles step places it). Non-numbers fail the model validation.
      def box_from(fields)
        values = fields.to_h.compact_blank
        return if values.empty?

        values.transform_values do |value|
          number = Float(value, exception: false)
          number && number % 1 == 0 ? number.to_i : (number || value)
        end
      end

      # Editing the text can break token offsets; say so instead of silently keeping bad tokens.
      def notice_after_save
        broken = @bubble.tokens.reject(&:valid?)
        return "Пузырь сохранён" if broken.empty?

        "Пузырь сохранён. Проверьте токены: #{broken.map(&:surface).join(", ")} больше не совпадают с текстом"
      end
  end
end
