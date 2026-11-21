require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::LayoutTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper

  setup do
    Ai::Llm::Fake.respond_with(ko_answer(panels: 8))
    @episode = Ai::Steps::Script.call(ko_series, panels: 8)
  end

  test "bubbles cascade from the top-left, alternating sides, inside the panel" do
    assert_equal 16, Ai::Steps::Layout.call(@episode)

    narration, speech = @episode.panels.first.bubbles.map(&:box)
    assert_equal({ "x" => 4, "y" => 3 }, narration.slice("x", "y"))
    assert_equal 96, speech["x"] + speech["w"], "second bubble on the right"
    assert_equal narration["y"] + narration["h"] + 2, speech["y"]
    @episode.bubbles.each do |bubble|
      assert bubble.valid?, bubble.errors.full_messages.inspect
      assert bubble.box["y"] + bubble.box["h"] <= 96
    end
    assert_equal({ "bubbles" => 16 }, @episode.generation_logs.find_by!(step: "layout").metadata.slice("bubbles"))
  end

  test "sizes follow the text: one short line, longer text wraps into a taller box" do
    layout = Ai::Steps::Layout.new(@episode)
    short = layout.box_for(Bubble.new(kind: "speech", text: "와!"), top: 3, side: :left, aspect_ratio: 0.8)
    long = layout.box_for(Bubble.new(kind: "speech", text: "나무꾼은 아주 오래된 쇠도끼를 들고 깊은 산속 연못 옆에서 일했어요."),
                          top: 3, side: :left, aspect_ratio: 0.8)

    assert_equal 26, short["w"], "minimum width"
    assert short["h"] < long["h"]
    assert long["w"] <= 64
  end

  test "boxes set by hand are kept unless force" do
    bubble = @episode.panels.first.bubbles.first
    bubble.update!(box: { "x" => 50, "y" => 60, "w" => 40, "h" => 10 })

    Ai::Steps::Layout.call(@episode)
    assert_equal 50, bubble.reload.box["x"]

    Ai::Steps::Layout.call(@episode, force: true)
    assert_equal 4, bubble.reload.box["x"]
  end

  test "chat episodes have no boxes" do
    Ai::Llm::Fake.respond_with(en_chat_answer)
    chat = Ai::Steps::Script.call(en_series, format: "chat")
    assert_equal 0, Ai::Steps::Layout.call(chat)
    assert chat.bubbles.all? { |b| b.box.nil? }
  end
end
