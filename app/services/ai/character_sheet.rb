module Ai
  # Character reference sheet: one image with four views of the character on a plain background, drawn in the
  # series art style (art_style, else style_prompt). Attached to character.sheet; the images step passes it as a
  # reference for every panel the character appears in. Cost and errors go to GenerationLog (step "sheets").
  #
  #   Ai::CharacterSheet.call(character)   # ~10–30 s, $0.04 with Seedream 4.5
  class CharacterSheet
    SIZE = "2560x1440" # 16:9 fits four views; above Seedream's 3.69 MP minimum

    def self.call(character) = new(character).call

    def initialize(character)
      @character = character
    end

    def prompt
      series = @character.series
      [
        series.art_style.presence || series.style_prompt,
        "Character model sheet of ONE character, #{@character.name}: #{@character.appearance_prompt.to_s.squish}",
        "Flat plain light-gray background everywhere, no scenery, no sparkles. Four views side by side: " \
        "full body front view, full body three-quarter view, head-and-shoulders close-up with a neutral face, " \
        "head-and-shoulders close-up smiling.",
        "Identical person in every view, the close-ups included: same face, hairstyle, facial hair, headwear, " \
        "accessories, same outfit with the same colors; even studio lighting, no props, no other people.",
        "No text, labels, names, numbers or color swatches."
      ].compact_blank.join("\n")
    end

    def call
      raise ArgumentError, "#{@character.key}: appearance_prompt is empty" if @character.appearance_prompt.blank?

      metadata = { "series_id" => @character.series_id, "character_id" => @character.id, "character" => @character.key }
      result = GenerationLog.track(step: "sheets", metadata:) do
        Ai.image(:sheets).generate(prompt:, size: SIZE)
      end
      image = result.image
      @character.sheet.attach(io: image.io, content_type: image.content_type,
                              filename: "#{@character.series.slug}-#{@character.key}#{File.extname(image.filename)}")
      result
    end
  end
end
