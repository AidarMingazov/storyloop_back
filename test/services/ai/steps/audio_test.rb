require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::AudioTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper
  include TokensTestHelper

  setup do
    ko_series.update!(narrator_voice: "Korean_Narrator")
    Ai::Llm::Fake.respond_with(ko_answer(panels: 2))
    @episode = Ai::Steps::Script.call(ko_series, panels: 2)
    @episode.panels.last.bubbles.last.update!(kind: "thought", character: ko_series.characters.find_by!(key: "spirit"))
    Ai::Llm::Fake.respond_with(markup_answer(@episode.panels.flat_map(&:bubbles)) { |text| ko_tokens(text) })
    Ai::Steps::Tokens.call(@episode)
  end

  test "bubbles in their speakers' voices, then every new dictionary form; one log" do
    summary = Ai::Steps::Audio.call(@episode)

    assert_equal({ "bubbles" => 4, "lemmas" => 8, "failed" => {} }, summary)
    assert @episode.bubbles.all? { |b| b.audio.attached? }
    assert Lexeme.where(language: "ko").all? { |l| l.audio.attached? }

    calls = Ai::Tts::Fake.calls
    by_text = calls.group_by { |c| c[:text] }
    assert_equal [ "Korean_Narrator" ], by_text["나무꾼이 연못에 도끼를 떨어뜨렸어요."].map { |c| c[:voice] }.uniq
    speech = calls.select { |c| c[:text] == "정직하게 말해요. 울지 마세요." }
    assert_equal [ [ "Korean_InnocentBoy", 1.0 ], [ "Korean_CalmLady", 0.95 ] ], speech.map { |c| [ c[:voice], c[:speed] ] }.sort.reverse,
                 "the woodcutter's voice; the spirit has none → default voice, slower thought"
    assert_equal [ "ko" ], calls.map { |c| c[:language] }.uniq
    assert_equal [ "Korean_CalmLady" ], calls.select { |c| c[:text] == "나무꾼이" }.map { |c| c[:voice] }, "lemmas in the default voice"

    log = @episode.generation_logs.find_by!(step: "audio")
    assert log.succeeded?
    assert_equal 12, log.metadata["calls"]
    assert_equal calls.sum { |c| c[:text].length }, log.characters
  end

  test "only what is missing is recorded again; failures are reported" do
    Ai::Steps::Audio.call(@episode)
    Ai::Tts::Fake.reset!
    assert_equal({ "bubbles" => 0, "lemmas" => 0, "failed" => {} }, Ai::Steps::Audio.call(@episode))

    bubble = @episode.bubbles.first
    Ai::Tts::Fake.respond_with(Ai::ContentRejected.new("minimax: 1026 sensitive"))
    summary = Ai::Steps::Audio.call(@episode, bubbles: [ bubble ])
    assert_equal({ "bubble #{bubble.id}" => "minimax: 1026 sensitive" }, summary["failed"])
  end

  test "English episodes use the English default voice" do
    Ai::Llm::Fake.respond_with(en_chat_answer)
    chat = Ai::Steps::Script.call(en_series, format: "chat")
    Ai::Steps::Audio.call(chat)
    assert_equal [ "English_CalmWoman" ], Ai::Tts::Fake.calls.map { |c| c[:voice] }.uniq
    assert_equal [ "en" ], Ai::Tts::Fake.calls.map { |c| c[:language] }.uniq
  end
end
