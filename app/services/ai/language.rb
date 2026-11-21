module Ai
  # What the pipeline knows about a language: its name for prompts and how to check text written in it.
  #   Ai::Language["ko"].length("안녕하세요!") # => 5 (Hangul syllables); Ai::Language["en"].length("I'm late") # => 2 (words)
  Language = Data.define(:code, :name, :script, :unit, :max_length, :foreign, :title_shape) do
    def self.[](code)
      self::ALL.fetch(code.to_s) { raise ConfigError, "language #{code.inspect} is not supported by the AI pipeline" }
    end

    # Length in the unit learners feel: Hangul syllables for Korean, words for alphabetic languages.
    def length(text) = text.to_s.scan(code == "ko" ? /\p{Hangul}/ : /[[:alpha:]][[:alpha:]'’-]*/).size

    def written_in?(text) = text.to_s.match?(script)
  end

  Language::ALL = {
    "ko" => Language.new(code: "ko", name: "Korean", script: /\p{Hangul}/, unit: "Hangul characters", max_length: 30,
                         foreign: /[A-Za-z0-9\p{Cyrillic}]/, title_shape: "<Korean title> · <English title>"),
    "en" => Language.new(code: "en", name: "English", script: /[A-Za-z]/, unit: "words", max_length: 14,
                         foreign: /[\p{Cyrillic}\p{Hangul}]/, title_shape: "<English title>"),
    "ru" => Language.new(code: "ru", name: "Russian", script: /\p{Cyrillic}/, unit: "words", max_length: 14,
                         foreign: /[\p{Hangul}]/, title_shape: "<Russian title>")
  }.freeze
end
