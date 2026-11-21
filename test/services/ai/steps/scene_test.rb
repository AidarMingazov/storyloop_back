require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::SceneTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper
  include SceneTestHelper

  def episode(panels: 3)
    @episode ||= begin
      Ai::Llm::Fake.respond_with(ko_answer(panels:))
      Ai::Steps::Script.call(ko_series, panels:).tap { Ai::Llm::Fake.reset! }
    end
  end

  test "tags every panel from its image prompt and lines in one call" do
    episode
    Ai::Llm::Fake.respond_with(scene_answer(3, focus: "woodcutter"))

    summary = Ai::Steps::Scene.call(episode)

    assert_equal({ "tagged" => 3, "failed" => {} }, summary)
    scene = episode.panels.first.reload.scene
    assert_equal({ "v" => 1, "focus" => "woodcutter", "elements" => [ "water" ] }, scene.slice("v", "focus", "elements"))
    assert_equal %w[exterior forest day clear daylight calm medium], scene.values_at(*%w[setting place time weather light mood shot])
    assert_equal 1, Ai::Llm::Fake.calls.size

    log = episode.generation_logs.find_by!(step: "scene")
    assert log.succeeded?
    assert_equal 3, log.metadata["tagged"]

    system, user = Ai::Llm::Fake.calls.first[:messages].map { |m| m[:content] }
    assert_includes system, "mood: calm | happy | romantic"
    assert_includes system, "woodcutter = Woodcutter, spirit = Mountain Spirit"
    assert_includes user, "Panel 2: Medium shot: Woodcutter by the pond, panel 2."
    assert_includes user, "woodcutter: 정직하게 말해요. 울지 마세요."
    assert_includes user, "narration: 나무꾼이 연못에 도끼를 떨어뜨렸어요."
  end

  test "names, case and extra elements are normalized instead of costing an attempt" do
    episode(panels: 1)
    answer = scene_answer(1, mood: " Romantic ", shot: "CLOSE", focus: "Mountain Spirit",
                             elements: %w[steam Steam lamps stars moon], comment: "unknown keys are dropped")
    Ai::Llm::Fake.respond_with(answer)

    Ai::Steps::Scene.call(episode)

    scene = episode.panels.first.reload.scene
    assert_equal [ "romantic", "close", "spirit", %w[steam lamps stars] ], scene.values_at("mood", "shot", "focus", "elements")
    assert_not scene.key?("comment")
    assert_equal 1, Ai::Llm::Fake.calls.size
  end

  test "wrong panels go back to the model; tags that passed are kept" do
    episode
    first = scene_answer([ 1, 3 ]).tap { |a| a["panels"][1]["mood"] = "grumpy" } # panel 2 missing, panel 3 wrong
    Ai::Llm::Fake.respond_with(first, scene_answer([ 2, 3 ], mood: "sad"))

    summary = Ai::Steps::Scene.call(episode)

    assert_equal({ "tagged" => 3, "failed" => {} }, summary)
    assert_equal %w[calm sad sad], episode.panels.reload.map { |p| p.scene["mood"] }
    retry_prompt = Ai::Llm::Fake.calls.last[:messages].last[:content]
    assert_match(/panel 2: panel 2 is missing/, retry_prompt)
    assert_match(/panel 3: mood: /, retry_prompt)
    assert_no_match(/panel 1/, retry_prompt)
  end

  test "panels still wrong after the attempts keep their old scene; nothing tagged fails the step" do
    episode
    Ai::Llm::Fake.respond_with(scene_answer([ 1 ], focus: "ghost"), scene_answer([ 1 ], focus: "ghost"))

    error = assert_raises(Ai::InvalidOutput) { Ai::Steps::Scene.call(episode) }
    assert_match(/not a character key/, error.message)
    assert episode.panels.reload.all? { |p| p.scene.blank? }
    log = episode.generation_logs.find_by!(step: "scene")
    assert log.failed?
    assert_equal %w[1 2 3], log.metadata["failed"].keys

    Ai::Llm::Fake.respond_with(scene_answer([ 1, 2 ]), scene_answer([ 1, 2 ]))
    summary = Ai::Steps::Scene.call(episode)
    assert_equal [ 2, [ "3" ] ], [ summary["tagged"], summary["failed"].keys ]
  end

  test "tagged panels are skipped unless forced; chat has nothing to tag" do
    episode(panels: 2)
    Ai::Llm::Fake.respond_with(scene_answer([ 1, 2 ]))
    Ai::Steps::Scene.call(episode)

    assert_equal({ "tagged" => 0, "failed" => {} }, Ai::Steps::Scene.call(episode))
    assert_equal 1, Ai::Llm::Fake.calls.size

    Ai::Llm::Fake.respond_with(scene_answer([ 1, 2 ], weather: "rain"))
    Ai::Steps::Scene.call(episode, force: true)
    assert_equal %w[rain rain], episode.panels.reload.map { |p| p.scene["weather"] }

    Ai::Llm::Fake.respond_with(en_chat_answer)
    chat = Ai::Steps::Script.call(en_series, format: "chat")
    calls = Ai::Llm::Fake.calls.size
    assert_equal({ "tagged" => 0, "failed" => {} }, Ai::Steps::Scene.call(chat))
    assert_equal calls, Ai::Llm::Fake.calls.size
  end
end
