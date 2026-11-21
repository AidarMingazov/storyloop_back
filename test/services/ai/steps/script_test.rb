require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::ScriptTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper

  test "a good answer becomes a draft episode with placeholder pictures and a linked log" do
    Ai::Llm::Fake.respond_with(ko_answer)

    episode = Ai::Steps::Script.call(ko_series)

    assert episode.draft?
    assert_equal [ 1, "webtoon", "A1", true ], [ episode.number, episode.format, episode.cefr_level, episode.free ]
    assert_equal "금도끼 · The Golden Axe", episode.title
    assert_equal 10, episode.panels.size
    assert_equal 20, episode.bubbles.size
    assert_equal 5, episode.estimated_minutes
    assert episode.panels.first.image.attached?
    assert_equal ko_series.characters.find_by!(key: "woodcutter"), episode.bubbles.where(kind: "speech").first.character
    assert_equal "Woodcutter", episode.script_json.dig("series", "characters", 0, "name")

    log = episode.generation_logs.sole
    assert log.succeeded?
    assert_equal "script", log.step
    assert_equal({ "number" => 1, "format" => "webtoon", "attempts" => 1, "warnings" => [] },
                 log.metadata.slice("number", "format", "attempts", "warnings"))
    assert_equal [ { json: true, max_tokens: 16_000 } ], Ai::Llm::Fake.calls.map { |c| c.slice(:json, :max_tokens) }
  end

  test "the model's own number, format and extra keys are ignored" do
    answer = ko_answer
    answer["episode"].merge!("number" => 99, "format" => "chat", "free" => false, "mood" => "sad")
    answer["episode"]["panels"][0]["camera"] = "drone"
    Ai::Llm::Fake.respond_with(answer)

    episode = Ai::Steps::Script.call(ko_series, number: 4)
    assert_equal [ 4, "webtoon", false ], [ episode.number, episode.format, episode.free ]
  end

  test "problems go back to the model and the second answer is used" do
    bad = ko_answer
    bad["episode"]["panels"][0]["bubbles"][1]["character"] = "dragon"
    Ai::Llm::Fake.respond_with(bad, ko_answer(title: "두 번째 · Second"))

    episode = Ai::Steps::Script.call(ko_series)

    assert_equal "두 번째 · Second", episode.title
    retry_messages = Ai::Llm::Fake.calls.last[:messages]
    assert_equal %w[system user assistant user], retry_messages.map { |m| m[:role] }
    assert_match(/Fix these problems.*panel 1 bubble 2: unknown character "dragon"/m, retry_messages.last[:content])
    assert_equal 2, GenerationLog.sole.metadata["attempts"]
    assert_equal [ [ "panel 1 bubble 2: unknown character \"dragon\", use one of woodcutter, spirit" ] ],
                 GenerationLog.sole.metadata["fixed_problems"]
    assert_equal 2, GenerationLog.sole.metadata["calls"]
  end

  test "three failed answers fail the log and create nothing" do
    Ai::Llm::Fake.respond_with("not json", { "episode" => { "title" => "x" } }, { "story" => "no" })

    error = assert_raises(Ai::InvalidOutput) { Ai::Steps::Script.call(ko_series) }
    assert_match(/failed the checks 3 times/, error.message)
    assert_not_empty error.problems
    assert_equal 0, ko_series.episodes.count
    assert GenerationLog.sole.failed?
  end

  test "a provider failure switches once to the fallback model" do
    Ai::Llm::Fake.respond_with(Ai::RateLimited.new("deepseek: HTTP 429", provider: "deepseek"), ko_answer)

    episode = Ai::Steps::Script.call(ko_series)
    assert_equal "anthropic/claude-haiku-5.5", episode.generation_logs.sole.model
  end

  test "a published episode is not overwritten" do
    Ai::Llm::Fake.respond_with(ko_answer)
    Ai::Steps::Script.call(ko_series).publish!

    assert_raises(ArgumentError) { Ai::Steps::Script.call(ko_series, number: 1) }
    assert_empty Ai::Llm::Fake.responses
  end

  test "regenerating a draft replaces its panels and keeps the episode" do
    Ai::Llm::Fake.respond_with(ko_answer, ko_answer(panels: 9, title: "다시 · Again"))
    first = Ai::Steps::Script.call(ko_series)
    second = Ai::Steps::Script.call(ko_series, number: 1)

    assert_equal first, second
    assert_equal [ "다시 · Again", 9 ], [ second.title, second.panels.count ]
    assert_equal 2, second.generation_logs.count
  end

  test "Korean prompt: speech levels, series memory and taught words" do
    Ai::Llm::Fake.respond_with(ko_answer)
    first = Ai::Steps::Script.call(ko_series)
    first.update!(synopsis: "He lost the iron axe.", target_words: %w[도끼 연못])

    system, user = Ai::Steps::Script.new(ko_series, brief: "The neighbor tries the trick", target_words: %w[욕심]).messages.map { |m| m[:content] }

    assert_includes system, "English-speaking adults learning Korean (CEFR A1)"
    assert_includes system, "woodcutter = Woodcutter (protagonist) — always speaks polite 해요체"
    assert_includes system, "spirit = Mountain Spirit — always speaks casual 반말"
    assert_includes system, "never a plain statement as an order"
    assert_includes system, "Episode 1 «금도끼 · The Golden Axe»: He lost the iron axe."
    assert_includes system, "do not choose them as target words again): 도끼, 연못"
    assert_includes system, "Ends with the moral."
    assert_includes system, "<Korean title> · <English title>"
    assert_equal "Write episode 2. Target words: 욕심. Brief: The neighbor tries the trick", user
  end

  test "English-Russian chat: prompt and episode" do
    step = Ai::Steps::Script.new(en_series, format: "chat")
    system = step.messages.first[:content]
    assert_includes system, "Russian-speaking adults learning English (CEFR A2)"
    assert_includes system, "3 parts"
    assert_includes system, "«ты» between friends"
    assert_includes system, "max 12 words per bubble"
    assert_not_includes system, "Image prompt rules"
    assert_not_includes system, "반말"

    Ai::Llm::Fake.respond_with(en_chat_answer)
    episode = step.call
    assert episode.format_chat?
    assert_equal [ "chat_message" ], episode.bubbles.map(&:kind).uniq
    assert_not episode.panels.first.image.attached?
  end

  test "unsupported language pair is a configuration error" do
    pair = LanguagePair.create!(code: "fr-ru", target_lang: "fr", native_lang: "ru")
    series = Series.create!(language_pair: pair, slug: "fr", title: "Fr", cefr_level: "A1")
    assert_raises(Ai::ConfigError) { Ai::Steps::Script.new(series) }
  end
end
