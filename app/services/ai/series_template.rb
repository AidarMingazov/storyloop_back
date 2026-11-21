module Ai
  # Series template db/templates/ai/series/<name>.yml → Series + Characters in the DB; character sheets are attached
  # from the template folder (<name>/characters/*.jpeg). Re-running updates the same series (language pair + slug)
  # without duplicates. An attached sheet is kept unless replace_sheets: true — it may have been regenerated in the
  # admin. Characters missing from the template are left alone (they may already have bubbles).
  #
  # tone, art_style, narrator_voice, speech_level and the sheet are inputs of the pipeline only: they are not part
  # of config/schemas/episode.json, and Episodes::Importer does not overwrite them.
  class SeriesTemplate
    DIR = Rails.root.join("db/templates/ai/series")
    SERIES_FIELDS = %w[title description genre cefr_level tone art_style style_prompt narrator_voice].freeze
    CHARACTER_FIELDS = %w[name appearance_prompt voice speech_level].freeze

    attr_reader :path, :data

    def self.names = DIR.glob("*.yml").map { |path| path.basename(".yml").to_s }.sort

    def self.load(name, **) = new(name).load(**)

    def initialize(name_or_path)
      @path = name_or_path.to_s.end_with?(".yml") ? Pathname(name_or_path) : DIR.join("#{name_or_path}.yml")
      raise ArgumentError, "no series template #{@path} (known: #{self.class.names.join(', ')})" unless @path.file?

      @data = YAML.safe_load_file(@path)
    end

    def load(replace_sheets: false)
      attrs = data.fetch("series")
      ActiveRecord::Base.transaction do
        pair = LanguagePair.find_by!(code: data.fetch("language_pair"))
        series = pair.series.find_or_initialize_by(slug: attrs.fetch("slug"))
        series.update!(attrs.slice(*SERIES_FIELDS))
        attrs.fetch("characters").each { |character| load_character(series, character, replace_sheets:) }
        series
      end
    end

    private
      def load_character(series, attrs, replace_sheets:)
        character = series.characters.find_or_initialize_by(key: attrs.fetch("key"))
        character.update!(attrs.slice(*CHARACTER_FIELDS).merge("protagonist" => attrs["protagonist"] || false))

        sheet = attrs["sheet"].presence && sheets_dir.join(attrs["sheet"])
        return unless sheet&.file? && (replace_sheets || !character.sheet.attached?)

        # read into memory: Active Storage uploads after the transaction commits, a File would be closed by then
        character.sheet.attach(io: StringIO.new(sheet.binread), filename: "#{series.slug}-#{character.key}#{sheet.extname}",
                               content_type: Marcel::MimeType.for(sheet))
      end

      def sheets_dir = path.dirname.join(path.basename(".yml"))
  end
end
