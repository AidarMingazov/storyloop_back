require "test_helper"

class Ai::TokenCheckTest < ActiveSupport::TestCase
  def check(text, tokens, target: "ko", native: "en")
    Ai::TokenCheck.new(text, tokens, target: Ai::Language[target], native: Ai::Language[native])
  end

  def ko(surface, lemma = surface, pos: "noun", **extra)
    { "surface" => surface, "lemma" => lemma, "pos" => pos, "translation" => "x", "romanization" => "ro" }.merge(extra.stringify_keys)
  end

  test "a full markup passes and gives offsets" do
    result = check("아이고, 짐이 너무 무거워...", [ ko("아이고", pos: "interjection"), ko("짐이", "짐"), ko("너무", pos: "adverb"),
                                                ko("무거워", "무겁다", pos: "adjective", politeness: "casual") ])
    assert result.ok?, result.problems.inspect
    assert_equal [ [ 0, 3 ], [ 5, 7 ], [ 8, 10 ], [ 11, 14 ] ], result.located.map { |_, s, e| [ s, e ] }
  end

  test "surfaces out of order, with punctuation or uncovered words are problems; good tokens are kept" do
    result = check("아이고, 짐이 너무 무거워...", [ ko("아이고,", pos: "interjection"), ko("너무", pos: "adverb"), ko("짐이", "짐") ])

    assert_includes result.problems, "아이고,: remove punctuation from the surface"
    assert_includes result.problems, "\"짐이\" not found in the text after the previous token (copy it exactly, no punctuation)"
    assert_includes result.problems, "not covered: 아이고 짐이 무거워 — every word needs a token"
    assert_equal [ "너무" ], result.located.map { |t, _, _| t["surface"] }
  end

  test "Korean fields: predicate lemmas in 다, romanization, politeness, breakdown, pos" do
    result = check("무거워", [ ko("무거워", "무겁", pos: "adjective", romanization: "Mugeowo", politeness: "rude",
                                breakdown: [ { "part" => "무겁", "role" => "root" } ]) ])
    assert_equal [ "무거워: lemma of a adjective must end in 다", "무거워: romanization must be lowercase Latin letters",
                   "무거워: politeness must be casual, polite or formal",
                   "무거워: breakdown items need part and role (stem, ending, particle, suffix)",
                   "not covered: 무거워 — every word needs a token" ], result.problems

    assert_includes check("짐", [ ko("짐", pos: "thing") ]).problems, "짐: unknown pos \"thing\""
  end

  test "English: multi-word tokens cover their words; translations must be Russian" do
    tokens = [ { "surface" => "I", "lemma" => "I", "pos" => "pronoun", "translation" => "я" },
               { "surface" => "ran into", "lemma" => "run into", "pos" => "phrasal_verb", "translation" => "встретила" },
               { "surface" => "Leo", "lemma" => "Leo", "pos" => "noun", "translation" => "Leo" } ]
    result = check("I ran into Leo!", tokens, target: "en", native: "ru")
    assert_equal [ "Leo: translation must be in Russian", "not covered: Leo — every word needs a token" ], result.problems

    tokens[2]["translation"] = "Лео"
    assert check("I ran into Leo!", tokens, target: "en", native: "ru").ok?
    assert_includes check("Hi", [], target: "en", native: "ru").problems, "no tokens"
  end
end
