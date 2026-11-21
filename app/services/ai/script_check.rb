module Ai
  # Checks of a generated episode document (config/schemas/episode.json shape) beyond what the model can be trusted
  # with. errors go back to the model for another attempt; warnings are only logged.
  #
  #   check = Ai::ScriptCheck.new(doc, target: Ai::Language["ko"], native: Ai::Language["en"],
  #                               characters: %w[woodcutter spirit], panels: 10)
  #   check.errors   # => ["panel 3 bubble 1: 34 Hangul characters, keep it under 30", …]
  class ScriptCheck
    # Writing on things comes out as garbled text in generated pictures.
    WRITING = /\b(menus?|signs?|signboards?|posters?|banners?|labels?|newspapers?|screens?|monitors?|captions?|text|letters?|notes?)\b/i
    NEGATED = /\b(no|without|not|never)\b[^.;]*/i # "No text or signs." is fine
    PANEL_SLACK = 2

    attr_reader :errors, :warnings

    def initialize(doc, target:, native:, characters:, panels:)
      @doc = doc
      @target = target
      @native = native
      @characters = characters
      @panels = panels
      @errors = []
      @warnings = []
      run
    end

    def ok? = errors.empty?

    private
      def episode = @doc.fetch("episode", {})
      def chat? = episode["format"] == "chat"

      def run
        schema_errors = Episodes::Importer.schema.validate(@doc).map { |e| "schema: #{e['error']} at #{e['data_pointer']}" }
        @errors.concat(schema_errors.first(10))
        check_panels
        check_target_words
      end

      def check_panels
        panels = Array(episode["panels"])
        unless (@panels - PANEL_SLACK..@panels + PANEL_SLACK).cover?(panels.size)
          @errors << "#{panels.size} panels, write #{@panels} (#{@panels - PANEL_SLACK}–#{@panels + PANEL_SLACK} is fine)"
        end
        @errors << "the episode has no bubbles at all" if panels.sum { |p| Array(p["bubbles"]).size }.zero?

        panels.each.with_index(1) do |panel, index|
          check_image_prompt(panel, index)
          @errors << "panel #{index}: a chat part needs messages" if chat? && Array(panel["bubbles"]).empty?
          Array(panel["bubbles"]).each.with_index(1) { |bubble, position| check_bubble(bubble, "panel #{index} bubble #{position}") }
        end
      end

      def check_image_prompt(panel, index)
        return if chat?

        prompt = panel["image_prompt"].to_s
        return @errors << "panel #{index}: image_prompt is missing" if prompt.blank?

        writing = prompt.gsub(NEGATED, "").scan(WRITING).flatten.uniq
        @errors << "panel #{index}: image_prompt mentions #{writing.join(', ')} — show the moment without anything written" if writing.any?
      end

      def check_bubble(bubble, where)
        kind = bubble["kind"]
        character = bubble["character"]
        if chat? && kind != "chat_message"
          @errors << "#{where}: chat episodes have only chat_message bubbles"
        elsif !chat? && kind == "chat_message"
          @errors << "#{where}: chat_message is only for chat episodes, use speech/thought/narration"
        end
        @errors << "#{where}: unknown character #{character.inspect}, use one of #{@characters.join(', ')}" if character && !@characters.include?(character)
        @errors << "#{where}: narration must have \"character\": null" if kind == "narration" && character
        @errors << "#{where}: #{kind} needs a character" if %w[speech thought chat_message].include?(kind) && character.blank?
        check_text(bubble["text"].to_s, where)
        check_translation(bubble["translation"].to_s, where)
      end

      def check_text(text, where)
        length = @target.length(text)
        @errors << "#{where}: #{length} #{@target.unit}, keep it under #{@target.max_length}" if length > @target.max_length
        @errors << "#{where}: the text is not written in #{@target.name}" if text.present? && !@target.written_in?(text)
        foreign = text.scan(@target.foreign).uniq
        @errors << "#{where}: remove #{foreign.join(' ')} from the #{@target.name} text" if foreign.any?
      end

      def check_translation(translation, where)
        if translation.blank?
          @errors << "#{where}: translation is missing"
        elsif !@native.written_in?(translation)
          @errors << "#{where}: translation must be in #{@native.name}"
        end
      end

      def check_target_words
        words = Array(episode["target_words"])
        @errors << "#{words.size} target_words, give 5–12" unless (5..12).cover?(words.size)

        text = Array(episode["panels"]).flat_map { |p| Array(p["bubbles"]).map { |b| b["text"].to_s } }.join("\n").downcase
        missing = words.reject { |word| text.match?(pattern(word)) }
        @warnings << "target words not found in the text (may be inflected): #{missing.join(', ')}" if missing.any?
      end

      # English: the first word ("run into" → run). Korean: the stem before (하)다, its last syllable matched by its
      # first consonant only, because endings change it (고치다 → 고쳐요, 차갑다 → 차가워요, 기다리다 → 기다려요).
      def pattern(word)
        word = word.to_s.downcase.strip
        return Regexp.new(Regexp.escape(word.split.first.to_s)) unless @target.code == "ko"

        return Regexp.new(Regexp.escape(word.delete_suffix("하다"))) if word.end_with?("하다") && word.length > 2

        stem = word.delete_suffix("다").presence || word
        last = stem[-1].ord - 0xAC00
        return Regexp.new(Regexp.escape(stem)) unless last.between?(0, 11_171)

        first = 0xAC00 + (last / 588 * 588)
        Regexp.new("#{Regexp.escape(stem[0...-1])}[#{first.chr(Encoding::UTF_8)}-#{(first + 587).chr(Encoding::UTF_8)}]")
      end
  end
end
