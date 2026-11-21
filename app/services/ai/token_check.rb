module Ai
  # Checks the model's tokens for one bubble: surfaces found in text order without overlaps, every word covered,
  # known parts of speech, Korean lemmas of predicates in 다, romanization and politeness in shape.
  #
  #   check = Ai::TokenCheck.new(bubble.text, tokens, target: Ai::Language["ko"], native: Ai::Language["en"])
  #   check.located  # => [[token_hash, start, end], …] — the tokens that can be saved
  #   check.problems # => ["\"무거워\" not found after the previous token", "not covered: 짐이"]
  class TokenCheck
    WORD = /\p{Hangul}+|[A-Za-z]+(?:['’][A-Za-z]+)*/
    BREAKDOWN_ROLES = %w[stem ending particle suffix].freeze

    attr_reader :located, :problems

    def initialize(text, tokens, target:, native:)
      @text = text.to_s
      @tokens = Array(tokens).select { |t| t.is_a?(Hash) }
      @target = target
      @native = native
      @located = []
      @problems = []
      run
    end

    def ok? = problems.empty?

    private
      def run
        @problems << "no tokens" if @tokens.empty? && @text.match?(WORD)
        cursor = 0
        @tokens.each do |token|
          surface = token["surface"].to_s
          start, finish = surface.present? && Token.locate(@text, surface, from: cursor)
          unless start
            @problems << "#{surface.inspect} not found in the text after the previous token (copy it exactly, no punctuation)"
            next
          end

          field_problems = fields(token)
          @problems.concat(field_problems.map { |problem| "#{surface}: #{problem}" })
          @located << [ token, start, finish ] if field_problems.empty?
          cursor = finish
        end
        check_coverage
      end

      def fields(token)
        problems = []
        problems << "remove punctuation from the surface" if token["surface"].to_s.match?(/\A[[:punct:]…]|[[:punct:]…]\z/)
        problems << "unknown pos #{token['pos'].inspect}" unless Lexeme::POS.include?(token["pos"])
        problems << "lemma is missing" if token["lemma"].blank?
        if token["translation"].blank?
          problems << "translation is missing"
        elsif !@native.written_in?(token["translation"]) && !token["translation"].match?(/\A[\p{P}\p{S}\s\d]*\z/)
          problems << "translation must be in #{@native.name}"
        end
        problems << "cefr #{token['cefr'].inspect} is not a CEFR level" if token["cefr"] && !Cefr::LEVELS.include?(token["cefr"])
        problems.concat(korean(token)) if @target.code == "ko"
        problems
      end

      def korean(token)
        problems = []
        if %w[verb adjective].include?(token["pos"]) && !token["lemma"].to_s.end_with?("다")
          problems << "lemma of a #{token['pos']} must end in 다"
        end
        romanization = token["romanization"].to_s
        problems << "romanization must be lowercase Latin letters" unless romanization.match?(/\A[a-z][a-z' -]*\z/)
        problems << "politeness must be casual, polite or formal" if token["politeness"] && !Token::POLITENESS.include?(token["politeness"])
        breakdown = token["breakdown"]
        if breakdown && !(breakdown.is_a?(Array) && breakdown.all? { |b| b.is_a?(Hash) && b["part"].present? && BREAKDOWN_ROLES.include?(b["role"]) })
          problems << "breakdown items need part and role (stem, ending, particle, suffix)"
        end
        problems
      end

      def check_coverage
        spans = @located.map { |_, start, finish| start...finish }
        missing = []
        @text.to_enum(:scan, WORD).each do
          match = Regexp.last_match
          word = match.begin(0)...match.end(0)
          missing << match[0] unless spans.any? { |span| span.cover?(word.begin) || word.cover?(span.begin) }
        end
        @problems << "not covered: #{missing.join(' ')} — every word needs a token" if missing.any?
      end
  end
end
