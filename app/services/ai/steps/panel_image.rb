module Ai
  module Steps
    # Pipeline step 2 for one panel: image_prompt + series style + sheets of the characters named in the prompt as
    # reference images → Ai.image(:images) → panel.image (replaces the placeholder). One GenerationLog per panel, so a
    # failed or bad panel can be redrawn alone (admin button, Ai::Steps::Images with panels:).
    class PanelImage
      MIN_PIXELS = 3_686_400 # Seedream 4.5 / 5.x refuse smaller pictures

      def self.call(panel) = new(panel).call

      # "1728x2160" for the default 0.8 — sides are multiples of 16, area above MIN_PIXELS.
      def self.size_for(aspect_ratio)
        height = (Math.sqrt(MIN_PIXELS / aspect_ratio) / 16).ceil * 16
        width = (height * aspect_ratio / 16).ceil * 16
        "#{width}x#{height}"
      end

      def initialize(panel)
        @panel = panel
        @episode = panel.episode
        @series = @episode.series
      end

      # Characters named (or keyed) in the image prompt, in the order of the series.
      def cast
        scene = @panel.image_prompt.to_s
        @cast ||= @series.characters.order(:id).select do |character|
          [ character.name, character.key ].any? { |word| scene.match?(/\b#{Regexp.escape(word)}\b/i) }
        end
      end

      def references = cast.select { |character| character.sheet.attached? }

      def prompt
        refs = references
        legend = refs.each_with_index.map { |c, i| "Image #{i + 1} is the character sheet of #{c.name}" }.join("; ")
        [
          @series.style_prompt,
          (if refs.any?
             "#{legend}. Draw each of them exactly as on their sheet (face, hair, facial hair, headwear, outfit and its colors), " \
             "but in a new pose for this scene. If the scene describes a change of look (a haircut, other clothes), " \
             "draw the change, not the sheet. Do not copy the sheet layout or its gray background."
           end),
          "Scene: #{@panel.image_prompt.to_s.squish}",
          ("Keep the top 25% of the frame calm and uncluttered (sky, wall or ceiling) for speech bubbles." if @panel.bubbles.any?),
          "Single vertical panel, no panel borders, no text, no letters, no speech bubbles."
        ].compact_blank.join("\n")
      end

      def call
        raise ArgumentError, "panel #{@panel.position + 1}: image_prompt is empty" if @panel.image_prompt.blank?

        metadata = { "panel_id" => @panel.id, "panel" => @panel.position + 1, "cast" => cast.map(&:key),
                     "references" => references.map(&:key) }
        result = GenerationLog.track(step: "images", episode: @episode, metadata:) do
          Ai.image(:images).generate(prompt:, references: references.map(&:sheet), size: self.class.size_for(@panel.aspect_ratio))
        end
        image = result.image
        @panel.image.attach(io: image.io, content_type: image.content_type,
                            filename: format("panel-%02d%s", @panel.position + 1, File.extname(image.filename)))
        result
      end
    end
  end
end
