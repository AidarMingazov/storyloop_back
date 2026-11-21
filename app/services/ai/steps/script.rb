module Ai
  module Steps
    # Pipeline step 1 "Scenario": series template + memory of earlier episodes → LLM (JSON mode) → episode document →
    # Ai::ScriptCheck → up to ATTEMPTS tries with the problems fed back → Episodes::Importer (draft, placeholder
    # pictures until step 2). Number, format, level and "free" are set here, not by the model.
    #
    #   Ai::Steps::Script.call(series)                                   # next number, webtoon, 10 panels
    #   Ai::Steps::Script.call(series, number: 2, format: "chat", brief: "Mia texts Sam about Leo", target_words: %w[…])
    class Script
      include FallbackChat

      ATTEMPTS = 3
      MAX_TOKENS = 16_000 # DeepSeek spends most of it on reasoning
      PANELS = { "chat" => 3 }.freeze
      DEFAULT_PANELS = 10
      FREE_EPISODES = 3
      MEMORY = 10 # previous episodes in the prompt
      SPEECH = { "casual" => "casual 반말", "polite" => "polite 해요체", "formal" => "formal 합쇼체" }.freeze

      attr_reader :series, :number, :format, :panels, :attempts, :warnings

      def self.call(series, **) = new(series, **).call

      def initialize(series, number: nil, format: "webtoon", panels: nil, brief: nil, target_words: [])
        raise ArgumentError, "unknown format #{format.inspect}" unless Episode::FORMATS.include?(format.to_s)

        @series = series
        @number = (number.presence || ((series.episodes.maximum(:number) || 0) + 1)).to_i
        @format = format.to_s
        @panels = (panels.presence || PANELS.fetch(@format, DEFAULT_PANELS)).to_i
        @brief = brief
        @target_words = Array(target_words).map(&:to_s).compact_blank
        @target = Language[series.language_pair.target_lang]
        @native = Language[series.language_pair.native_lang]
        @warnings = []
      end

      def call
        existing = series.episodes.find_by(number:)
        raise ArgumentError, "episode #{number} of #{series.slug} is published, unpublish it first" if existing&.published?

        request = { "number" => number, "format" => format, "panels" => panels, "brief" => @brief, "requested_words" => @target_words }
        GenerationLog.track(step: "script", episode: existing, metadata: request) do |log|
          doc = generate
          episode = Episodes::Importer.call(doc, status: "draft")
          log.update!(episode:, metadata: log.metadata.merge("attempts" => attempts, "warnings" => warnings,
                                                             "fixed_problems" => @problems_seen))
          episode
        end
      end

      def messages
        Prompt.messages(
          "scenario",
          target: @target, native: @native, cefr: series.cefr_level, format:, number:, panels:,
          genre: series.genre, tone: series.tone.to_s, title: series.title, description: series.description,
          characters:, previous:, taught_words:, target_words: @target_words, brief: @brief,
          language_rules: Prompt.render("languages/#{@target.code}", cefr: series.cefr_level, native: @native)
        )
      end

      private
        def generate
          messages = self.messages
          problems = []
          @problems_seen = []
          ATTEMPTS.times do |attempt|
            @attempts = attempt + 1
            result = chat(:script, messages, json: true, max_tokens: MAX_TOKENS)
            doc = document(result.json)
            check = doc && ScriptCheck.new(doc, target: @target, native: @native, characters: character_keys, panels:)
            problems = check ? check.errors : [ "the answer is not a JSON object with \"episode\": #{result.json_error || result.finish_reason}" ]
            problems << "the answer was cut off (finish_reason: length) — keep it shorter" if result.finish_reason == "length"
            if problems.empty?
              @warnings = check.warnings
              return doc
            end

            @problems_seen << problems.first(5)

            messages += [ { role: "assistant", content: result.text },
                          { role: "user", content: "Fix these problems and return the full corrected JSON:\n- #{problems.join("\n- ")}" } ]
          end
          raise InvalidOutput.new("#{series.slug} episode #{number}: the script failed the checks #{ATTEMPTS} times", problems:)
        end

        def document(json)
          episode = json.is_a?(Hash) && (json["episode"].is_a?(Hash) ? json["episode"] : json)
          return unless episode.is_a?(Hash) && episode.key?("panels")

          { "language_pair" => series.language_pair.code, "series" => series_attributes, "episode" => episode_attributes(episode) }
        end

        def episode_attributes(episode)
          panels = Array(episode["panels"]).map { |panel| panel_attributes(panel) }
          bubbles = panels.sum { |panel| panel["bubbles"].size }
          episode.slice("title", "synopsis", "target_words").merge(
            "number" => number, "format" => format, "cefr_level" => series.cefr_level, "free" => number <= FREE_EPISODES,
            "estimated_minutes" => [ (bubbles / 4.0).ceil, 2 ].max, "panels" => panels
          )
        end

        # Keys the schema does not know are dropped instead of costing another attempt.
        def panel_attributes(panel)
          return { "bubbles" => [] } unless panel.is_a?(Hash)

          bubbles = Array(panel["bubbles"]).select { |b| b.is_a?(Hash) }.map { |b| b.slice("kind", "character", "text", "translation") }
          attrs = { "bubbles" => bubbles }
          attrs.merge!("image_prompt" => panel["image_prompt"], "layout" => { "aspect_ratio" => Panel::DEFAULT_ASPECT_RATIO }) unless format == "chat"
          attrs
        end

        def series_attributes
          {
            "slug" => series.slug, "title" => series.title, "description" => series.description, "genre" => series.genre,
            "cefr_level" => series.cefr_level, "style_prompt" => series.style_prompt,
            "characters" => series.characters.order(:id).map do |c|
              { "key" => c.key, "name" => c.name, "appearance_prompt" => c.appearance_prompt, "protagonist" => c.protagonist,
                "voice" => c.voice }.compact
            end
          }.compact
        end

        def characters
          series.characters.order(:id).map do |c|
            { key: c.key, name: c.name, protagonist: c.protagonist?, speech: (SPEECH[c.speech_level] if @target.code == "ko") }
          end
        end

        def character_keys = series.characters.pluck(:key)

        def earlier_episodes = series.episodes.where(number: ...number).order(:number)

        def previous
          earlier_episodes.last(MEMORY).map { |e| "Episode #{e.number} «#{e.title}»: #{e.synopsis}" }.join("\n")
        end

        def taught_words = earlier_episodes.flat_map(&:target_words).uniq
    end
  end
end
