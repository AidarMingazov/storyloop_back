module Ai
  module Steps
    # Pipeline step 4 "Word markup": every bubble's words → tokens (lemma, part of speech, meaning here and in the
    # dictionary, CEFR, note; Korean adds romanization, breakdown and politeness). One request per CHUNK bubbles;
    # bubbles that fail Ai::TokenCheck are asked again on their own with their problems (up to ATTEMPTS). A bubble
    # that never passes keeps the tokens that were right and is listed in the log as "unresolved" for the review
    # screen. Lexemes are shared across episodes (find or create by language + lemma + pos).
    #
    #   Ai::Steps::Tokens.call(episode)                  # => {"tokens" => 120, "unresolved" => {"p3b1" => [...]}}
    #   Ai::Steps::Tokens.call(episode, bubbles: [bubble])
    class Tokens
      include FallbackChat

      ATTEMPTS = 3
      CHUNK = 20
      MAX_TOKENS = 16_000

      def self.call(episode, **) = new(episode, **).call

      def initialize(episode, bubbles: nil, chunk: CHUNK)
        @episode = episode
        @bubbles = bubbles || episode.panels.includes(bubbles: :character).flat_map(&:bubbles)
        @chunk = chunk
        pair = episode.series.language_pair
        @pair = pair
        @target = Language[pair.target_lang]
        @native = Language[pair.native_lang]
      end

      def call
        GenerationLog.track(step: "tokens", episode: @episode, metadata: { "bubbles" => @bubbles.size }) do |log|
          located = {}
          unresolved = {}
          @bubbles.each_slice(@chunk) { |chunk| markup(chunk, located, unresolved) }
          count = save(located)
          summary = { "tokens" => count, "unresolved" => unresolved }
          log.update!(metadata: log.metadata.merge(summary))
          summary
        end
      end

      def messages(bubbles, problems = {})
        Prompt.messages(
          "markup",
          target: @target, native: @native, cefr: @episode.cefr_level, target_words: @episode.target_words,
          bubbles: bubbles.map { |b| { id: id_for(b), speaker: b.character&.name || "Narrator", kind: b.kind, text: b.text, translation: b.translation } },
          problems:, language_rules: Prompt.render("markup/#{@target.code}", native: @native)
        )
      end

      private
        def markup(chunk, located, unresolved)
          pending = chunk.index_by { |bubble| id_for(bubble) }
          best = {}
          problems = {}
          ATTEMPTS.times do
            break if pending.empty?

            answer = ask(pending.values, problems)
            problems = {}
            pending.each do |id, bubble|
              check = TokenCheck.new(bubble.text, answer[id], target: @target, native: @native)
              best[id] = check.located if best[id].nil? || check.located.size > best[id].size
              check.ok? ? located[bubble] = check.located : problems[id] = check.problems.first(6)
            end
            pending.reject! { |_, bubble| located.key?(bubble) }
          end
          pending.each do |id, bubble|
            located[bubble] = best[id] || []
            unresolved[id] = problems[id]
          end
        end

        def ask(bubbles, problems)
          result = chat(:tokens, messages(bubbles, problems), json: true, max_tokens: MAX_TOKENS, temperature: 0.1)
          items = result.json.is_a?(Hash) ? Array(result.json["bubbles"]) : []
          items.select { |item| item.is_a?(Hash) }.to_h { |item| [ item["id"].to_s, item["tokens"] ] }
        end

        def save(located)
          lexemes = Episodes::Importer::LexemeCache.new(@pair)
          ActiveRecord::Base.transaction do
            located.sum do |bubble, tokens|
              bubble.tokens.destroy_all
              tokens.each do |attrs, start, finish|
                bubble.tokens.create!(
                  lexeme: lexemes.fetch(attrs), start_offset: start, end_offset: finish, surface: attrs["surface"],
                  context_translation: attrs["translation"], context_note: attrs["note"].presence,
                  romanization: attrs["romanization"].presence, breakdown: attrs["breakdown"].presence,
                  politeness: attrs["politeness"].presence
                )
              end
              tokens.size
            end
          end
        end

        def id_for(bubble) = "p#{bubble.panel.position + 1}b#{bubble.position + 1}"
    end
  end
end
