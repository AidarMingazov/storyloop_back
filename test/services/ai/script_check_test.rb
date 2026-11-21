require "test_helper"
require_relative "../../test_helpers/script_test_helper"

class Ai::ScriptCheckTest < ActiveSupport::TestCase
  include ScriptTestHelper

  def doc(answer, pair: "ko-en", format: "webtoon")
    episode = answer["episode"].merge("number" => 1, "format" => format)
    episode["panels"] = episode["panels"].map { |p| format == "chat" ? p : p.merge("layout" => { "aspect_ratio" => 0.8 }) }
    { "language_pair" => pair, "series" => { "slug" => "s", "title" => "S", "cefr_level" => "A1", "characters" => [ { "key" => "k", "name" => "K" } ] },
      "episode" => episode }
  end

  def check(doc, target: "ko", native: "en", characters: %w[woodcutter spirit], panels: 10)
    Ai::ScriptCheck.new(doc, target: Ai::Language[target], native: Ai::Language[native], characters:, panels:)
  end

  test "a good Korean episode passes" do
    result = check(doc(ko_answer))
    assert result.ok?, result.errors.inspect
    assert_empty result.warnings
  end

  test "a good English chat passes" do
    result = check(doc(en_chat_answer, pair: "en-ru", format: "chat"), target: "en", native: "ru", characters: %w[della jim], panels: 3)
    assert result.ok?, result.errors.inspect
  end

  test "story rules: characters, narration, panel count, target words" do
    answer = ko_answer(panels: 6)
    bubbles = answer["episode"]["panels"][0]["bubbles"]
    bubbles[0]["character"] = "woodcutter"
    bubbles[1]["character"] = "dragon"
    answer["episode"]["panels"][1]["bubbles"][1]["character"] = nil
    answer["episode"]["target_words"] = %w[하나]

    errors = check(doc(answer)).errors
    assert_includes errors, "6 panels, write 10 (8–12 is fine)"
    assert_includes errors, "panel 1 bubble 1: narration must have \"character\": null"
    assert_includes errors, "panel 1 bubble 2: unknown character \"dragon\", use one of woodcutter, spirit"
    assert_includes errors, "panel 2 bubble 2: speech needs a character"
    assert_includes errors, "1 target_words, give 5–12"
  end

  test "Korean text rules: length, Latin and digits, translation language" do
    answer = ko_answer
    bubble = answer["episode"]["panels"][2]["bubbles"][1]
    bubble["text"] = "나무꾼은 아주 오래된 쇠도끼를 들고 깊은 산속 연못 옆에서 하루 종일 일했어요."
    answer["episode"]["panels"][3]["bubbles"][1].merge!("text" => "OK, 3시에 만나요!", "translation" => "나무꾼")

    errors = check(doc(answer)).errors
    assert_includes errors, "panel 3 bubble 2: 32 Hangul characters, keep it under 30"
    assert_includes errors, "panel 4 bubble 2: remove O K 3 from the Korean text"
    assert_includes errors, "panel 4 bubble 2: translation must be in English"
  end

  test "English text rules: words and Cyrillic" do
    answer = en_chat_answer
    answer["episode"]["panels"][0]["bubbles"][0]["text"] = "I really really want to buy you the most beautiful present in the whole city"
    answer["episode"]["panels"][1]["bubbles"][1].merge!("text" => "Привет, Jim!", "translation" => "Hi")

    errors = check(doc(answer, pair: "en-ru", format: "chat"), target: "en", native: "ru", characters: %w[della jim], panels: 3).errors
    assert_includes errors, "panel 1 bubble 1: 15 words, keep it under 14"
    assert_includes errors, "panel 2 bubble 2: remove П р и в е т from the English text"
    assert_includes errors, "panel 2 bubble 2: translation must be in Russian"
  end

  test "image prompts must not ask for writing; negations are fine" do
    answer = ko_answer
    answer["episode"]["panels"][0]["image_prompt"] = "Close-up: Woodcutter reads the menu on a sign."
    answer["episode"]["panels"][1]["image_prompt"] = "Wide shot of the pond. No text or signs."
    answer["episode"]["panels"][2]["image_prompt"] = ""

    errors = check(doc(answer)).errors
    assert_includes errors, "panel 1: image_prompt mentions menu, sign — show the moment without anything written"
    assert_includes errors, "panel 3: image_prompt is missing"
    assert_equal 2, errors.size
  end

  test "format rules: chat bubbles only in chat episodes" do
    answer = ko_answer
    answer["episode"]["panels"][0]["bubbles"][1]["kind"] = "chat_message"
    assert_includes check(doc(answer)).errors, "panel 1 bubble 2: chat_message is only for chat episodes, use speech/thought/narration"

    chat = en_chat_answer
    chat["episode"]["panels"][0]["bubbles"][0]["kind"] = "speech"
    errors = check(doc(chat, pair: "en-ru", format: "chat"), target: "en", native: "ru", characters: %w[della jim], panels: 3).errors
    assert_includes errors, "panel 1 bubble 1: chat episodes have only chat_message bubbles"
  end

  test "schema errors are reported and missing target words are only a warning" do
    answer = ko_answer
    answer["episode"]["panels"][0]["bubbles"][0]["kind"] = "shout"
    answer["episode"]["target_words"] = %w[나무꾼 도끼 연못 정직하다 사랑하다]

    result = check(doc(answer))
    assert result.errors.any? { |e| e.start_with?("schema:") && e.include?("/episode/panels/0/bubbles/0/kind") }
    assert_equal [ "target words not found in the text (may be inflected): 사랑하다" ], result.warnings
  end

  test "Korean target words are found in inflected forms" do
    answer = ko_answer
    answer["episode"]["target_words"] = %w[고치다 차갑다 기다리다 인사하다 어렵다 무섭다]
    answer["episode"]["panels"][0]["bubbles"][1]["text"] = "고쳐요. 차가워요. 기다려요. 인사해요. 어려워요. 무서워요."
    assert_empty check(doc(answer)).warnings
  end
end
