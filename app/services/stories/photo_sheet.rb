module Stories
  # Character sheet from a learner's photo (7.11): four views of the character in the story's art style, with the
  # clearest photo of the person or animal as the reference (config/ai.yml step photo_sheets — Seedream 5.0 lite kept
  # people recognizable and flat 2D in the wave 6 research). The images step then draws every panel from this sheet.
  class PhotoSheet
    SIZE = Ai::CharacterSheet::SIZE

    def self.call(character, photo) = new(character, photo).call

    # photo: JPEG bytes (StoryRequest#photo_jpeg)
    def initialize(character, photo)
      @character = character
      @photo = photo
    end

    def prompt
      [
        @character.series.art_style,
        "Character model sheet of ONE character, #{@character.name}, drawn after the reference photo (image 1): " \
        "#{@character.appearance_prompt.to_s.squish}",
        "NOT photorealistic in any view: a 2D cartoon character in the style above, recognizable by the distinctive " \
        "features of the photo — hair, face shape, glasses, facial hair, build, outfit and its colors. Ignore the photo's background.",
        "Flat plain light-gray background everywhere, no scenery. Four views side by side: full body front view, full body " \
        "three-quarter view, head-and-shoulders close-up with a neutral face, head-and-shoulders close-up smiling.",
        "Identical character in every view, the close-ups included; even studio lighting, no props, no other people or animals.",
        "No text, labels, names, numbers or color swatches."
      ].compact_blank.join("\n")
    end

    def call
      metadata = { "series_id" => @character.series_id, "character_id" => @character.id, "character" => @character.key, "photo" => true }
      result = GenerationLog.track(step: "sheets", episode: @character.series.episodes.first, metadata:) do
        Ai.image(:photo_sheets).generate(prompt:, references: [ StringIO.new(@photo) ], size: SIZE)
      end
      image = result.image
      @character.sheet.attach(io: image.io, content_type: image.content_type,
                              filename: "#{@character.series.slug}-#{@character.key}#{File.extname(image.filename)}")
      result
    end
  end
end
