require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::TokensTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper
  include TokensTestHelper

  def markup_calls = Ai::Llm::Fake.calls.select { |call| call[:step] == "tokens" }

  setup do
    Ai::Llm::Fake.respond_with(ko_answer(panels: 3))
    @episode = Ai::Steps::Script.call(ko_series, panels: 3)
    @bubbles = @episode.panels.flat_map(&:bubbles)
  end

  test "one request marks up every bubble; lexemes are shared" do
    Ai::Llm::Fake.respond_with(markup_answer(@bubbles) { |text| ko_tokens(text) })

    summary = Ai::Steps::Tokens.call(@episode)

    assert_equal({ "tokens" => 24, "unresolved" => {} }, summary)
    assert_equal 1, markup_calls.size
    assert_equal 24, @episode.tokens.count
    assert_equal 8, Lexeme.where(language: "ko").count, "the same 8 words in every panel"
    token = @bubbles.first.tokens.first
    assert_equal [ "나무꾼이", 0, 4, "word", "mal" ], [ token.surface, token.start_offset, token.end_offset, token.context_translation, token.romanization ]
    assert_equal "word", token.lexeme.translation_for("en")
    log = @episode.generation_logs.find_by!(step: "tokens")
    assert_equal({ "bubbles" => 6, "tokens" => 24, "unresolved" => {} }, log.metadata.slice("bubbles", "tokens", "unresolved"))

    system, user = markup_calls.first[:messages].map { |m| m[:content] }
    assert_includes system, "Korean comic dialogue for English-speaking learners (CEFR A1)"
    assert_includes system, "Verbs/adjectives end in 다"
    assert_includes system, "always give them a note): 나무꾼, 도끼, 연못, 정직하다, 울다"
    assert_includes user, "p1b2 [Woodcutter, speech]: 정직하게 말해요. 울지 마세요.  (EN: I'm honest. Don't cry.)"
  end

  test "only the bubbles with problems are asked again, with their problems" do
    first = markup_answer(@bubbles) { |text| ko_tokens(text) }
    first["bubbles"][1]["tokens"][0]["surface"] = "정직하게."
    retry_answer = markup_answer([ @bubbles[1] ]) { |text| ko_tokens(text) }
    Ai::Llm::Fake.respond_with(first, retry_answer)

    assert_empty Ai::Steps::Tokens.call(@episode)["unresolved"]

    user = Ai::Llm::Fake.calls.last[:messages].last[:content]
    assert_equal 1, user.scan(/^p\d+b\d+ \[/).size
    assert_includes user, "p1b2: \"정직하게.\" not found in the text after the previous token"
    assert_equal 4, @bubbles[1].tokens.count
  end

  test "a cut-off answer is asked again in smaller requests" do
    Ai::Llm::Fake.respond_with(Ai::Llm::Fake::CutOff.new('{"bubbles": [{"id": "p1b1", "tokens": ['),
                               *@bubbles.each_slice(3).map { |slice| markup_answer(slice) { |t| ko_tokens(t) } })

    assert_empty Ai::Steps::Tokens.call(@episode)["unresolved"]
    assert_equal [ 6, 3, 3 ], markup_calls.map { |call| call[:messages].last[:content].scan(/^p\d+b\d+ \[/).size }
    assert_equal 24, @episode.tokens.count
  end

  test "a bubble that never passes keeps its good tokens and is reported" do
    broken = ->(answer) { answer.tap { |a| a["bubbles"].find { |b| b["id"] == "p2b1" }["tokens"].pop } }
    Ai::Llm::Fake.respond_with(broken.call(markup_answer(@bubbles) { |t| ko_tokens(t) }),
                               broken.call(markup_answer([ @bubbles[2] ]) { |t| ko_tokens(t) }),
                               broken.call(markup_answer([ @bubbles[2] ]) { |t| ko_tokens(t) }))

    summary = Ai::Steps::Tokens.call(@episode)

    assert_equal [ "p2b1" ], summary["unresolved"].keys
    assert_match(/not covered: 떨어뜨렸어요/, summary["unresolved"]["p2b1"].join)
    assert_equal 3, @bubbles[2].tokens.count
    assert @episode.generation_logs.find_by!(step: "tokens").succeeded?
  end

  test "bubbles are sent in chunks; a rerun replaces the tokens" do
    @bubbles.each_slice(4) { |slice| Ai::Llm::Fake.respond_with(markup_answer(slice) { |t| ko_tokens(t) }) }
    Ai::Steps::Tokens.call(@episode, chunk: 4)
    assert_equal 2, markup_calls.size

    Ai::Llm::Fake.respond_with(markup_answer([ @bubbles[0] ]) { |t| ko_tokens(t).first(2) + ko_tokens(t).drop(2) })
    Ai::Steps::Tokens.call(@episode, bubbles: [ @bubbles[0] ])
    assert_equal 4, @bubbles[0].tokens.count
    assert_equal 24, @episode.tokens.count
  end

  test "English-Russian: prompt rules and Russian translations" do
    Ai::Llm::Fake.respond_with(en_chat_answer)
    chat = Ai::Steps::Script.call(en_series, format: "chat")
    bubbles = chat.panels.flat_map(&:bubbles)
    Ai::Llm::Fake.respond_with(markup_answer(bubbles) { |text| en_tokens(text) })

    assert_empty Ai::Steps::Tokens.call(chat)["unresolved"]

    system, user = Ai::Llm::Fake.calls.last[:messages].map { |m| m[:content] }
    assert_includes system, "English comic dialogue for Russian-speaking learners (CEFR A2)"
    assert_includes system, "Contractions are one token"
    assert_includes system, "Russian meaning in THIS sentence"
    assert_not_includes system, "romanization:"
    assert_includes user, "(RU: Я не сдамся. Хочу тебе подарок!)"
    assert_equal "слово", chat.tokens.first.lexeme.translation_for("ru")
  end

  test "the fallback model takes over when the main one fails" do
    Ai::Llm::Fake.respond_with(Ai::InsufficientBalance.new("openrouter: HTTP 402", provider: "openrouter"),
                               markup_answer(@bubbles) { |t| ko_tokens(t) })
    Ai::Steps::Tokens.call(@episode)
    assert_equal "deepseek-flash", @episode.generation_logs.find_by!(step: "tokens").model
  end
end
