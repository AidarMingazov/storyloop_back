require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"
require_relative "../../../test_helpers/script_test_helper"

class Ai::Steps::ImagesTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper

  setup do
    ko_series.characters.find_by!(key: "woodcutter").sheet.attach(io: StringIO.new("sheet"), filename: "w.webp", content_type: "image/webp")
    answer = ko_answer(panels: 3)
    answer["episode"]["panels"][1].merge!("image_prompt" => "Wide shot: the mountain spirit rises from the pond.", "bubbles" => [])
    answer["episode"]["panels"][2]["image_prompt"] = "Close-up of Woodcutter and the Mountain Spirit."
    Ai::Llm::Fake.respond_with(answer)
    @episode = Ai::Steps::Script.call(ko_series, panels: 3)
    @panels = @episode.panels.to_a
  end

  test "size keeps the aspect ratio above Seedream's minimum" do
    assert_equal "1728x2160", Ai::Steps::PanelImage.size_for(0.8)
    width, height = Ai::Steps::PanelImage.size_for(1.5).split("x").map(&:to_i)
    assert width * height >= Ai::Steps::PanelImage::MIN_PIXELS
    assert_in_delta 1.5, width.to_f / height, 0.02
  end

  test "prompt: style, the cast's sheets as references, room for bubbles" do
    first = Ai::Steps::PanelImage.new(@panels[0])
    assert_equal %w[woodcutter], first.cast.map(&:key)
    assert_equal [ "Watercolor.",
                   "Image 1 is the character sheet of Woodcutter. Draw each of them exactly as on their sheet " \
                   "(face, hair, facial hair, headwear, outfit and its colors), but in a new pose for this scene. " \
                   "If the scene describes a change of look (a haircut, other clothes), draw the change, not the sheet. " \
                   "Do not copy the sheet layout or its gray background.",
                   "Scene: Medium shot: Woodcutter by the pond, panel 1.",
                   "Keep the top 25% of the frame calm and uncluttered (sky, wall or ceiling) for speech bubbles.",
                   "Single vertical panel, no panel borders, no text, no letters, no speech bubbles." ], first.prompt.lines(chomp: true)

    silent = Ai::Steps::PanelImage.new(@panels[1])
    assert_equal %w[spirit], silent.cast.map(&:key), "found by key"
    assert_empty silent.references, "the spirit has no sheet yet"
    assert_not_includes silent.prompt, "character sheet"
    assert_not_includes silent.prompt, "top 25%"
  end

  test "draws every placeholder panel with references, one log per panel" do
    result = Ai::Steps::Images.call(@episode)

    assert result.ok?
    assert_equal @panels, result.drawn
    @panels.each(&:reload)
    assert @panels.none?(&:placeholder_image?)
    assert_equal "panel-01.webp", @panels[0].image.filename.to_s
    calls = Ai::Image::Fake.calls.sort_by { |c| c[:prompt] }
    assert_equal [ 1, 0, 1 ], @panels.map { |p| calls.find { |c| c[:prompt].include?(p.image_prompt) }[:references] }
    assert_equal [ "1728x2160" ], calls.map { |c| c[:size] }.uniq

    logs = @episode.generation_logs.where(step: "images").order(:id)
    assert_equal 3, logs.size
    assert logs.all?(&:succeeded?)
    assert_equal({ "panel" => 3, "cast" => %w[woodcutter spirit], "references" => %w[woodcutter] },
                 logs.find { |l| l.metadata["panel"] == 3 }.metadata.slice("panel", "cast", "references"))

    assert_empty Ai::Steps::Images.call(@episode).drawn, "nothing left to draw"
  end

  test "a rejected panel keeps its placeholder; the rest are drawn" do
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("seedream: rejected by the safety filter"))

    result = Ai::Steps::Images.call(@episode, threads: 1)

    assert_not result.ok?
    assert_equal [ @panels[0] ], result.failed.keys
    assert_kind_of Ai::ContentRejected, result.failed[@panels[0]]
    assert @panels[0].reload.placeholder_image?
    assert_equal 2, result.drawn.size
  end

  test "given panels are redrawn even when they already have a picture; the job redraws one" do
    Ai::Steps::Images.call(@episode)
    Ai::Image::Fake.reset!

    Ai::Steps::Images.call(@episode, panels: [ @panels[1] ])
    assert_equal 1, Ai::Image::Fake.calls.size

    GeneratePanelImageJob.perform_now(@panels[2])
    assert_equal 2, Ai::Image::Fake.calls.size
  end

  test "chat episodes need no pictures" do
    Ai::Llm::Fake.respond_with(en_chat_answer)
    chat = Ai::Steps::Script.call(en_series, format: "chat")
    assert_empty Ai::Steps::Images.call(chat).drawn
  end
end
