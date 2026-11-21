module Stories
  # An episode in another language pair (7.8): a copy with origin_episode, the same pictures (they carry no text; the
  # blobs are shared), the same characters and sheets; the model rewrites every bubble in the new target language at
  # the episode's level with the native-language translation (structure kept, Ai::ScriptCheck for the language
  # rules, retries with the problems), then layout, word markup and voice-over run again.
  #
  #   Stories::Translation.call(episode, LanguagePair.find_by!(code: "en-ru"))  # → the new episode, status review/draft
  #
  # A user story becomes a user story of the same author and visibility (published after moderation by
  # TranslateEpisodeJob); a catalog episode goes into the series of the same slug in the other pair, for review.
  class Translation
    include Ai::Steps::FallbackChat

    ATTEMPTS = 3
    MAX_TOKENS = 16_000

    attr_reader :episode, :pair

    def self.call(...) = new(...).call

    def self.existing(episode, pair) = Episode.joins(:series).find_by(origin_episode: episode, series: { language_pair_id: pair.id })

    def initialize(episode, pair)
      raise ArgumentError, "episode #{episode.id} is already in #{pair.code}" if episode.series.language_pair_id == pair.id

      @episode = episode
      @pair = pair
      @source = Ai::Language[episode.series.language_pair.target_lang]
      @target = Ai::Language[pair.target_lang]
      @native = Ai::Language[pair.native_lang]
    end

    def call
      series = target_series
      copy_characters(series)
      translated = GenerationLog.track(step: "script", metadata: { "translation_of" => episode.id, "pair" => pair.code }) do |log|
        doc = translate(series)
        copy = Episodes::Importer.call(doc, status: "draft", placeholders: false)
        log.update!(episode: copy, metadata: log.metadata.merge("attempts" => @attempts))
        copy
      end
      translated.update!(origin_episode: episode)
      translated.series.update!(title: translated.title) if series.source_user? # a user story is named by its series
      copy_images(translated)
      Ai::Steps::Layout.call(translated, force: true) if translated.format_webtoon?
      Ai::Steps::Tokens.call(translated)
      Ai::Steps::Audio.call(translated)
      translated
    end

    def messages
      Ai::Prompt.messages(
        "translate", source: @source, target: @target, native: @native, cefr: episode.cefr_level, format: episode.format,
                     characters: episode.series.characters.order(:id).map { |c| { key: c.key, name: c.name } }, panels: original,
                     language_rules: Ai::Prompt.render("languages/#{@target.code}", cefr: episode.cefr_level, native: @native)
      )
    end

    private
      def source_panels = @source_panels ||= episode.panels.includes(bubbles: :character, image_attachment: :blob).order(:position).to_a

      def original
        source_panels.map do |panel|
          { "bubbles" => panel.bubbles.sort_by(&:position).map { |b| { "kind" => b.kind, "character" => b.character&.name, "text" => b.text } } }
        end
      end

      def translate(series)
        messages = self.messages
        problems = []
        ATTEMPTS.times do |attempt|
          @attempts = attempt + 1
          result = chat(:script, messages, json: true, max_tokens: MAX_TOKENS)
          doc, problems = document(result.json, series)
          if doc
            check = Ai::ScriptCheck.new(doc, target: @target, native: @native, characters: series.characters.pluck(:key), panels: source_panels.size)
            problems = check.errors
            return doc if problems.empty?
          end
          messages += [ { role: "assistant", content: result.text },
                        { role: "user", content: "Fix these problems and return the full corrected JSON:\n- #{problems.first(20).join("\n- ")}" } ]
        end
        raise Ai::InvalidOutput.new("translation of episode #{episode.id} into #{pair.code} failed the checks #{ATTEMPTS} times", problems:)
      end

      # The model's text in the original's structure → [episode document, nil] or [nil, problems].
      def document(json, series)
        answer = json.is_a?(Hash) && (json["episode"].is_a?(Hash) ? json["episode"] : json)
        return [ nil, [ "the answer is not a JSON object with \"episode\"" ] ] unless answer.is_a?(Hash)

        panels = Array(answer["panels"])
        return [ nil, [ "#{panels.size} panels, the original has #{source_panels.size}: keep every panel" ] ] if panels.size != source_panels.size

        problems = []
        doc_panels = source_panels.each_with_index.map do |panel, index|
          bubbles = Array(panels[index].is_a?(Hash) ? panels[index]["bubbles"] : nil)
          originals = panel.bubbles.sort_by(&:position)
          problems << "panel #{index + 1}: #{bubbles.size} bubbles, the original has #{originals.size}" if bubbles.size != originals.size
          { "bubbles" => originals.each_with_index.map do |bubble, position|
              written = bubbles[position].is_a?(Hash) ? bubbles[position] : {}
              { "kind" => bubble.kind, "character" => bubble.character&.key, "text" => written["text"].to_s.strip,
                "translation" => written["translation"].to_s.strip, "box" => bubble.box }.compact
            end }.merge(panel_picture(panel))
        end
        return [ nil, problems ] if problems.any?

        [ { "language_pair" => pair.code, "series" => series_attributes(series),
            "episode" => answer.slice("title", "synopsis", "target_words").merge(
              "number" => number(series), "format" => episode.format, "cefr_level" => episode.cefr_level, "free" => episode.free,
              "estimated_minutes" => episode.estimated_minutes, "panels" => doc_panels
            ).compact }, nil ]
      end

      def panel_picture(panel)
        return {} if episode.format_chat?

        { "image_prompt" => panel.image_prompt.presence || "Reused picture of panel #{panel.position + 1}.", "layout" => panel.layout.presence }.compact
      end

      def number(series) = series.source_user? ? 1 : episode.number

      def series_attributes(series)
        { "slug" => series.slug, "title" => series.title, "description" => series.description, "genre" => series.genre,
          "cefr_level" => series.cefr_level, "style_prompt" => series.style_prompt,
          "characters" => series.characters.order(:id).map do |c|
            { "key" => c.key, "name" => c.name, "appearance_prompt" => c.appearance_prompt, "protagonist" => c.protagonist, "voice" => c.voice }.compact
          end }.compact
      end

      def target_series
        source = episode.series
        if source.source_user?
          Series.create!(source: :user, author: source.author, language_pair: pair, slug: "u-#{SecureRandom.base36(10)}",
                         title: source.title, genre: source.genre, cefr_level: source.cefr_level, visibility: source.visibility,
                         moderation_state: :pending, description: source.description)
        else
          pair.series.find_or_create_by!(slug: source.slug) do |series|
            series.assign_attributes(title: source.title, description: source.description, genre: source.genre, cefr_level: source.cefr_level)
          end
        end.tap do |series|
          series.update!(style_prompt: source.style_prompt, art_style: source.art_style, tone: source.tone,
                         narrator_voice: (source.narrator_voice if same_voice_language?))
        end
      end

      def same_voice_language? = @source.code == @target.code

      # Same keys, names and sheets (one shared blob); voices of the new target language where we know them.
      def copy_characters(series)
        episode.series.characters.includes(sheet_attachment: :blob).find_each do |original|
          character = series.characters.find_or_initialize_by(key: original.key)
          character.update!(name: original.name, appearance_prompt: original.appearance_prompt, protagonist: original.protagonist,
                            speech_level: (original.speech_level if @target.code == "ko"), voice: voice_for(original))
          character.sheet.attach(original.sheet.blob) if original.sheet.attached? && character.sheet.blob != original.sheet.blob
        end
      end

      def voice_for(character)
        return character.voice if same_voice_language?

        story_request = episode.series.story_requests.order(:created_at).last
        cast_voice = Cast.find(story_request&.cast_key)&.characters&.find { |c| c["key"] == character.key }&.dig("voice", @target.code)
        gender = StoryRequest::VOICES.find { |_, voices| voices.value?(character.voice) }&.first
        cast_voice || (StoryRequest::VOICES.dig(gender, @target.code) if gender)
      end

      def copy_images(translated)
        pictures = source_panels.index_by(&:position)
        translated.panels.each do |panel|
          blob = pictures[panel.position]&.image&.blob
          panel.image.attach(blob) if blob
        end
      end
  end
end
