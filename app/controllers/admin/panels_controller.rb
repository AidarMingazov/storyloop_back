module Admin
  class PanelsController < BaseController
    before_action :set_panel

    def edit
    end

    def redraw
      GeneratePanelImageJob.perform_later(@panel)
      redirect_to admin_episode_path(@panel.episode, anchor: dom_id(@panel)), notice: "Кадр #{@panel.position + 1} перерисовывается (~30 с)"
    end

    def update
      attrs = params.expect(panel: %i[image_prompt layout_json image])
      layout = parse_json_field(attrs.delete(:layout_json))
      if layout == :invalid
        @panel.errors.add(:layout, "не JSON")
        return render(:edit, status: :unprocessable_entity)
      end

      if @panel.update(attrs.merge(layout: layout || {}))
        redirect_to admin_episode_path(@panel.episode, anchor: dom_id(@panel)), notice: "Кадр сохранён"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_panel
        @panel = Panel.find(params[:id])
      end
  end
end
