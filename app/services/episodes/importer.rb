module Episodes
  # Imports one episode JSON (config/schemas/episode.json) — hand-written seeds today,
  # output of pipeline step 1 later. Re-importing the same series slug + episode number
  # replaces the episode's panels, bubbles and tokens; lexemes are reused.
  class Importer
    SCHEMA_PATH = Rails.root.join("config/schemas/episode.json")

    class Invalid < StandardError
      attr_reader :details

      def initialize(details)
        @details = Array(details)
        super("Episode JSON is invalid:\n  " + @details.join("\n  "))
      end
    end

    def self.schema
      @schema ||= JSONSchemer.schema(SCHEMA_PATH)
    end

    def self.call(...) = new(...).call

    # data   — parsed JSON Hash or a JSON string
    # status — status for the imported episode (pipeline output goes to review)
    # base_dir — where relative panel image paths are resolved
    def initialize(data, status: "review", base_dir: nil, placeholders: true)
      @data = data.is_a?(String) ? JSON.parse(data) : data.deep_stringify_keys
      @status = status
      @base_dir = base_dir && Pathname(base_dir)
      @placeholders = placeholders
    rescue JSON::ParserError => e
      raise Invalid, "not JSON: #{e.message}"
    end

    def call
      validate_schema!

      ActiveRecord::Base.transaction do
        pair = LanguagePair.find_by!(code: @data["language_pair"])
        series = upsert_series(pair)
        characters = upsert_characters(series)
        episode = upsert_episode(series)
        import_panels(episode, characters, pair)
        episode
      end
    rescue ActiveRecord::RecordNotFound => e
      raise Invalid, e.message
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, "#{e.record.class.name}: #{e.record.errors.full_messages.to_sentence}"
    end

    private
      def validate_schema!
        errors = self.class.schema.validate(@data).map { |e| "#{e["data_pointer"].presence || "/"}: #{e["error"]}" }
        raise Invalid, errors if errors.any?
      end

      def upsert_series(pair)
        attrs = @data["series"]
        series = pair.series.find_or_initialize_by(slug: attrs["slug"])
        series.update!(attrs.slice("title", "description", "genre", "cefr_level", "style_prompt"))
        series.published! if @status == "published" && series.draft?
        series
      end

      def upsert_characters(series)
        @data["series"]["characters"].to_h do |attrs|
          character = series.characters.find_or_initialize_by(key: attrs["key"])
          character.update!(attrs.slice("name", "appearance_prompt", "voice").merge(protagonist: attrs["protagonist"] || false))
          [ character.key, character ]
        end
      end

      def upsert_episode(series)
        attrs = @data["episode"]
        episode = series.episodes.find_or_initialize_by(number: attrs["number"])
        episode.panels.destroy_all if episode.persisted?
        episode.update!(
          title: attrs["title"],
          format: attrs["format"],
          cefr_level: attrs["cefr_level"] || series.cefr_level,
          free: attrs.fetch("free", false),
          estimated_minutes: attrs["estimated_minutes"],
          synopsis: attrs["synopsis"],
          target_words: attrs["target_words"] || [],
          script_json: @data,
          status: @status
        )
        episode
      end

      def import_panels(episode, characters, pair)
        lexemes = LexemeCache.new(pair)

        @data["episode"]["panels"].each_with_index do |panel_attrs, panel_index|
          panel = episode.panels.create!(
            position: panel_index,
            image_prompt: panel_attrs["image_prompt"],
            layout: panel_attrs["layout"] || {}
          )
          attach_image(panel, panel_attrs, episode)

          panel_attrs["bubbles"].each_with_index do |bubble_attrs, bubble_index|
            import_bubble(panel, bubble_attrs, bubble_index, characters, lexemes, pair)
          end
        end
      end

      def import_bubble(panel, attrs, position, characters, lexemes, pair)
        where = "panel #{panel.position + 1}, bubble #{position + 1}"
        character = attrs["character"] && characters.fetch(attrs["character"]) do
          raise Invalid, "#{where}: unknown character #{attrs["character"].inspect}"
        end

        bubble = panel.bubbles.create!(
          position: position,
          kind: attrs["kind"],
          character: character,
          text: attrs["text"],
          translation: attrs["translation"],
          box: attrs["box"]
        )

        cursor = 0
        (attrs["tokens"] || []).each do |token_attrs|
          start, finish = token_offsets(bubble.text, token_attrs, cursor, where)
          bubble.tokens.create!(
            lexeme: lexemes.fetch(token_attrs),
            start_offset: start,
            end_offset: finish,
            surface: token_attrs["surface"],
            context_translation: token_attrs["translation"],
            context_note: token_attrs["note"],
            romanization: token_attrs["romanization"],
            breakdown: token_attrs["breakdown"],
            politeness: token_attrs["politeness"]
          )
          cursor = finish
        end
      end

      # Explicit offsets must slice exactly the surface; missing offsets are found in text order.
      def token_offsets(text, attrs, cursor, where)
        surface = attrs["surface"]
        if attrs["start"]
          start = attrs["start"]
          finish = attrs["end"] || start + surface.length
        else
          start, finish = Token.locate(text, surface, from: cursor)
          raise Invalid, "#{where}: token #{surface.inspect} not found in #{text.inspect} after offset #{cursor}" unless start
        end
        raise Invalid, "#{where}: token #{surface.inspect} overlaps the previous token" if start < cursor
        [ start, finish ]
      end

      def attach_image(panel, attrs, episode)
        if attrs["image"]
          raise Invalid, "panel #{panel.position + 1}: image paths need base_dir" unless @base_dir
          path = @base_dir.join(attrs["image"])
          raise Invalid, "panel #{panel.position + 1}: image not found: #{path}" unless path.file?
          panel.image.attach(io: path.open("rb"), filename: path.basename.to_s)
        elsif @placeholders && !episode.format_chat?
          panel.image.attach(PlaceholderImage.for(panel))
        end
      end

      # Finds or creates lexemes by (language, lemma, pos) and fills in missing data.
      class LexemeCache
        def initialize(pair)
          @pair = pair
          @cache = {}
        end

        def fetch(attrs)
          key = [ attrs["lemma"], attrs["pos"] ]
          @cache[key] ||= find_or_create(attrs)
        end

        private
          def find_or_create(attrs)
            lexeme = Lexeme.find_or_initialize_by(language: @pair.target_lang, lemma: attrs["lemma"], pos: attrs["pos"])
            native = @pair.native_lang
            lexeme.translations = lexeme.translations.merge(native => attrs["lemma_translation"] || attrs["translation"]) if lexeme.translations[native].blank?
            lexeme.cefr_level ||= attrs["cefr"]
            lexeme.romanization ||= attrs["lemma_romanization"]
            lexeme.save! if lexeme.changed?
            lexeme
          end
      end
  end
end
