require "vips"

module Episodes
  # Writes what the AI made for a series back into its seed JSON (db/seeds/episodes/<pair>/NN.json) and the media
  # folder next to it, so a fresh database (db:seed on staging or production) gets the same pictures, voices and
  # recordings without paying for them again (Episodes::Importer reads them):
  #   series narrator_voice; characters' voice, appearance_prompt and sheet (media/sheets/<key>.jpg);
  #   panel images, placeholders skipped (media/NN/panel-PP.webp, at most PANEL_WIDTH wide);
  #   bubble recordings (media/NN/bubble-PP-BB.mp3); recorded dictionary forms as tokens' lemma_audio (media/words/).
  # Texts stay as written in the JSON: a panel or bubble that differs from the database stops the export.
  #
  #   Episodes::Exporter.call(series)  # => {"files" => 5, "images" => 43, "recordings" => 96, "sheets" => 4, "words" => 214}
  class Exporter
    PANEL_WIDTH = 1280 # px: phones show ~1170 at most
    SHEET_SIZE = 1600
    AUDIO_EXTENSIONS = { "audio/mpeg" => ".mp3", "audio/wav" => ".wav", "audio/x-wav" => ".wav", "audio/ogg" => ".ogg" }.freeze
    SHARED = %w[media/sheets media/words].freeze # files several episodes point to

    class Mismatch < StandardError; end

    def self.call(...) = new(...).call

    def initialize(series, dir: nil)
      @series = series
      @dir = Pathname(dir.presence || Rails.root.join("db/seeds/episodes", series.language_pair.code))
      @language = series.language_pair.target_lang
      @written = Hash.new { |hash, key| hash[key] = {} } # kind => {record id => relative path}
    end

    def call
      files = seed_files
      raise Mismatch, "no seed JSON for #{@series.slug} in #{@dir}" if files.empty?

      files.each do |file, data|
        episode = @series.episodes.find_by(number: data.dig("episode", "number")) or
          raise Mismatch, "#{file.basename}: episode ##{data.dig("episode", "number")} is not in the database"
        export_series(data["series"])
        export_panels(episode, data["episode"]["panels"], file)
        file.write(JSON.pretty_generate(data) + "\n")
      end
      prune_shared
      { "files" => files.size }.merge(@written.transform_values(&:size))
    end

    private
      def seed_files
        @dir.glob("*.json").sort.filter_map do |file|
          data = JSON.parse(file.read)
          [ file, data ] if data.dig("series", "slug") == @series.slug
        end
      end

      def export_series(attrs)
        put(attrs, "narrator_voice", @series.narrator_voice, after: "style_prompt") if @series.narrator_voice.present?
        attrs["characters"].each do |character_attrs|
          character = @series.characters.find_by(key: character_attrs["key"]) or next
          character_attrs["appearance_prompt"] = character.appearance_prompt if character.appearance_prompt.present?
          character_attrs["voice"] = character.voice if character.voice.present?
          next unless character.sheet.attached?
          character_attrs["sheet"] = once("sheets", character) { write("media/sheets/#{character.key}.jpg", jpeg(character.sheet.download)) }
        end
      end

      def export_panels(episode, panels, file)
        folder = format("media/%02d", episode.number)
        FileUtils.rm_rf(@dir.join(folder)) # what is left of an earlier export
        records = episode.panels.includes(bubbles: { audio_attachment: :blob }).to_a
        check!(records.size == panels.size, file, "#{panels.size} panels, the database has #{records.size}")

        panels.zip(records).each_with_index do |(attrs, panel), index|
          if drawn?(panel)
            name = format("%s/panel-%02d.webp", folder, index + 1)
            put(attrs, "image", once("images", panel) { write(name, webp(panel.image.download)) }, after: "image_prompt")
          end
          export_bubbles(attrs["bubbles"], panel.bubbles.sort_by(&:position), folder, index, file)
        end
      end

      def export_bubbles(bubbles, records, folder, panel_index, file)
        check!(records.size == bubbles.size, file, "panel #{panel_index + 1}: #{bubbles.size} bubbles, the database has #{records.size}")
        bubbles.zip(records).each_with_index do |(attrs, bubble), index|
          check!(attrs["text"] == bubble.text, file, "panel #{panel_index + 1}, bubble #{index + 1}: #{attrs["text"].inspect} ≠ #{bubble.text.inspect}")
          if bubble.audio.attached?
            name = format("%s/bubble-%02d-%02d%s", folder, panel_index + 1, index + 1, extension(bubble.audio))
            put(attrs, "audio", once("recordings", bubble) { write(name, bubble.audio.download) }, after: %w[box translation text])
          end
          (attrs["tokens"] || []).each { |token| export_word(token) }
        end
      end

      def export_word(token)
        lexeme = lexeme(token["lemma"], token["pos"])
        return unless lexeme&.audio&.attached?
        token["lemma_audio"] = once("words", lexeme) do
          name = lexeme.lemma.parameterize.presence || lexeme.pos
          write("media/words/#{name}-#{Digest::MD5.hexdigest("#{lexeme.lemma}/#{lexeme.pos}")[0, 8]}#{extension(lexeme.audio)}", lexeme.audio.download)
        end
      end

      def lexeme(lemma, pos)
        @lexemes ||= {}
        @lexemes.fetch([ lemma, pos ]) { @lexemes[[ lemma, pos ]] = Lexeme.with_attached_audio.find_by(language: @language, lemma:, pos:) }
      end

      # Placeholders (Episodes::PlaceholderImage) are made again on import.
      def drawn?(panel) = panel.image.attached? && !panel.image.filename.to_s.start_with?("placeholder")

      def once(kind, record) = @written[kind][record.id] ||= yield

      def write(relative, bytes)
        path = @dir.join(relative)
        path.dirname.mkpath
        path.binwrite(bytes) unless path.file? && path.binread == bytes
        relative
      end

      def webp(bytes) = Vips::Image.thumbnail_buffer(bytes, PANEL_WIDTH, height: 10_000, size: :down).webpsave_buffer(Q: 82, strip: true)
      def jpeg(bytes) = Vips::Image.thumbnail_buffer(bytes, SHEET_SIZE, height: SHEET_SIZE, size: :down).jpegsave_buffer(Q: 88, strip: true)
      def extension(attachment) = AUDIO_EXTENSIONS[attachment.content_type] || File.extname(attachment.filename.to_s).presence || ".mp3"

      # Sheets and word recordings that no seed JSON in the folder points to any more.
      def prune_shared
        used = @dir.glob("*.json").flat_map { |file| file.read.scan(%r{"(media/(?:sheets|words)/[^"]+)"}).flatten }.to_set
        SHARED.flat_map { |folder| @dir.join(folder).glob("*") }.each do |path|
          path.delete unless used.include?(path.relative_path_from(@dir).to_s)
        end
      end

      def check!(ok, file, message)
        raise Mismatch, "#{file.basename}: #{message}" unless ok
      end

      # Puts the key right after the first of `after` that is there (or at the end), so the JSON stays readable.
      def put(hash, key, value, after:)
        pairs = hash.to_a.reject { |k, _| k == key }
        index = Array(after).filter_map { |name| pairs.index { |k, _| k == name } }.first
        pairs.insert(index ? index + 1 : pairs.size, [ key, value ])
        hash.replace(pairs.to_h)
      end
  end
end
