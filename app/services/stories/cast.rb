module Stories
  # A ready cast for user stories (7.4): characters with reference sheets, the art style and voices, from
  # db/templates/ai/casts/<key>.yml (see the README there). The story's own series gets a copy (#cast_into), so the
  # wave 6 pipeline draws and voices it like a catalog series. Sheets are shared: every copy attaches the same blob
  # (Active Storage keeps a blob while any attachment uses it — the foreign key stops a purge).
  #
  #   Stories::Cast.for(mode: "theme", theme: "school")  # → the school cast
  #   Stories::Cast.fetch("cafe").cast_into(series)
  class Cast
    DIR = Rails.root.join("db/templates/ai/casts")
    TEMPLATES = Rails.root.join("db/templates/ai")
    DEFAULT = "cafe" # an idea or own text without a chosen cast: modern everyday characters

    attr_reader :key, :data

    class << self
      def all = DIR.glob("*.yml").sort.map { |path| new(path) }
      def keys = DIR.glob("*.yml").map { |path| path.basename(".yml").to_s }.sort
      def find(key) = key.present? && keys.include?(key.to_s) ? new(DIR.join("#{key}.yml")) : nil
      def fetch(key) = find(key) || raise(KeyError, "no cast #{key.inspect} (known: #{keys.join(', ')})")
      def for_theme(theme) = all.find { |cast| cast.themes.include?(theme.to_s) }

      # The cast a request is drawn with: the one picked on the form, else the theme's, a random one for
      # "surprise me", the everyday cast otherwise.
      def for(mode:, theme: nil, cast: nil, random: Random)
        find(cast) ||
          (mode.to_s == "theme" && for_theme(theme)) ||
          (all.sample(random:) if mode.to_s == "surprise") ||
          fetch(DEFAULT)
      end
    end

    def initialize(path)
      @path = Pathname(path)
      @key = @path.basename(".yml").to_s
      @data = YAML.safe_load_file(@path)
    end

    def title(locale = I18n.locale) = data.fetch("title").then { |t| t[locale.to_s] || t["en"] }
    def themes = Array(data["themes"])
    def characters = data.fetch("characters")

    def name_for(character, lang) = character.fetch("names").then { |names| names[lang.to_s] || names["en"] }

    # Shown on the form: names in the language of the story.
    def names(lang) = characters.map { |character| name_for(character, lang) }

    def sheet_path(character)
      path = character["sheet"].presence && TEMPLATES.join(character["sheet"])
      path if path&.file?
    end

    def sheets? = characters.all? { |character| sheet_path(character) }

    def protagonist = characters.find { |character| character["protagonist"] } || characters.first

    # The blob of a character sheet, uploaded once and reused (found by checksum). create: false only looks it up
    # (the form shows previews of casts already used, without uploading anything during a page view).
    def sheet_blob(character, create: true)
      path = sheet_path(character) or return
      checksum = self.class.checksum(path)
      ActiveStorage::Blob.find_by(checksum:, byte_size: path.size) ||
        (ActiveStorage::Blob.create_and_upload!(io: StringIO.new(path.binread), filename: "cast-#{key}-#{character['key']}#{path.extname}",
                                                content_type: Marcel::MimeType.for(path)) if create)
    end

    # MD5 of a sheet file, remembered while the file is unchanged.
    def self.checksum(path)
      @checksums ||= {}
      @checksums[[ path.to_s, path.mtime ]] ||= OpenSSL::Digest::MD5.file(path).base64digest
    end

    # Copies style, voices and characters (with their sheets) into the story's series. Safe to run again.
    def cast_into(series)
      lang = series.language_pair.target_lang
      series.update!(art_style: data["art_style"], style_prompt: data["style_prompt"], tone: data["tone"],
                     narrator_voice: voice(data["narrator_voice"], lang), genre: series.genre.presence || data["genre"])
      characters.each do |attrs|
        character = series.characters.find_or_initialize_by(key: attrs.fetch("key"))
        character.update!(name: name_for(attrs, lang), appearance_prompt: attrs["appearance_prompt"].to_s.squish,
                          protagonist: attrs["protagonist"] || false, voice: voice(attrs["voice"], lang),
                          speech_level: (attrs["speech_level"] if lang == "ko"))
        blob = sheet_blob(attrs)
        character.sheet.attach(blob) if blob && character.sheet.blob != blob
      end
      series
    end

    private
      def voice(value, lang) = value.is_a?(Hash) ? value[lang.to_s] : value
  end
end
