require "test_helper"
require_relative "../../test_helpers/ai_test_helper"
require_relative "../../test_helpers/script_test_helper"

class Ai::PipelineTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper
  include SceneTestHelper
  include TokensTestHelper

  # Fake LLM answers in call order: the script, the scene tags, then the markup of every bubble of that script.
  def script_and_markup(answer)
    markup = { "bubbles" => answer["episode"]["panels"].each_with_index.flat_map do |panel, p|
      panel["bubbles"].each_with_index.map { |bubble, b| { "id" => "p#{p + 1}b#{b + 1}", "tokens" => ko_tokens(bubble["text"]) } }
    end }
    Ai::Llm::Fake.respond_with(answer, scene_answer(answer["episode"]["panels"].size), markup)
  end

  test "generate runs every step and leaves the episode for review" do
    script_and_markup(ko_answer(panels: 3))

    episode = Ai::Pipeline.generate(ko_series, panels: 3, brief: "The axe falls")

    assert episode.review?
    assert episode.panels.reload.none?(&:placeholder_image?)
    assert episode.bubbles.reload.all?(&:box)
    assert_equal 24, episode.tokens.count
    audio = episode.generation_logs.find_by!(step: "audio").metadata
    assert_equal [ 6, {} ], [ audio["bubbles"], audio["failed"] ], audio.inspect
    assert episode.bubbles.reload.all? { |b| b.audio.attached? }
    assert_equal %w[script scene images images images layout tokens audio], episode.generation_logs.order(:id).pluck(:step)
    assert episode.panels.all? { |panel| panel.scene["place"] == "forest" }

    status = Ai::PipelineStatus.new(episode)
    assert_equal %w[succeeded] * 6, status.rows.map(&:status)
    assert_equal "кадров с тегами: 3", status.rows.find { |r| r.step == "scene" }.notes
    assert_equal "нарисовано 3 из 3", status.rows.find { |r| r.step == "images" }.notes
    assert_equal "токенов: 24", status.rows.find { |r| r.step == "tokens" }.notes
    assert_empty status.unresolved_bubbles
  end

  test "a failing step stops the run and returns the episode to draft" do
    Ai::Llm::Fake.respond_with(ko_answer(panels: 3), scene_answer(3), Ai::Unauthorized.new("openrouter: 401", provider: "openrouter"),
                               Ai::Unauthorized.new("deepseek: 401", provider: "deepseek"))

    assert_raises(Ai::Unauthorized) { Ai::Pipeline.generate(ko_series, panels: 3) }

    episode = ko_series.episodes.sole
    assert episode.draft?
    assert_not episode.generation_logs.exists?(step: "audio")
    row = Ai::PipelineStatus.new(episode).rows.find { |r| r.step == "tokens" }
    assert_equal "failed", row.status
    assert_match(/401/, row.error)
  end

  test "a failing scene step is logged and the run goes on" do
    Ai::Llm::Fake.respond_with(ko_answer(panels: 2), Ai::Unauthorized.new("openrouter: 401", provider: "openrouter"),
                               Ai::Unauthorized.new("deepseek: 401", provider: "deepseek"),
                               { "bubbles" => [] }, { "bubbles" => [] }, { "bubbles" => [] })

    episode = Ai::Pipeline.generate(ko_series, panels: 2)

    assert episode.review?
    assert episode.panels.all? { |panel| panel.scene.blank? }
    row = Ai::PipelineStatus.new(episode).rows.find { |r| r.step == "scene" }
    assert_equal "failed", row.status
    assert_match(/401/, row.error)
    assert episode.generation_logs.exists?(step: "audio")

    Ai::Llm::Fake.respond_with(scene_answer(2, weather: "snow"))
    Ai::Pipeline.rerun(episode, "scene")
    assert_equal %w[snow snow], episode.panels.reload.map { |panel| panel.scene["weather"] }
    assert_equal %w[script scene images images layout tokens audio scene], episode.generation_logs.order(:id).pluck(:step)
  end

  test "rerun redoes the step with force and its dependents" do
    script_and_markup(ko_answer(panels: 2))
    episode = Ai::Pipeline.generate(ko_series, panels: 2)
    episode.bubbles.first.update!(box: { "x" => 50, "y" => 50, "w" => 30, "h" => 10 })
    Ai::Image::Fake.reset!
    Ai::Tts::Fake.reset!

    Ai::Pipeline.rerun(episode, "layout")
    assert_equal 4, episode.bubbles.first.reload.box["x"], "force re-places boxes set by hand"
    assert_empty Ai::Image::Fake.calls

    Ai::Pipeline.rerun(episode, "images")
    assert_equal 2, Ai::Image::Fake.calls.size, "every panel redrawn"

    bubble = episode.bubbles.first
    Ai::Llm::Fake.respond_with({ "bubbles" => [ { "id" => "p1b1", "tokens" => ko_tokens(bubble.text) } ] })
    Ai::Pipeline.rerun(episode, "tokens", bubbles: [ bubble ])
    assert_equal [ "tokens", "audio" ], episode.generation_logs.order(:id).last(2).map(&:step)
    assert_empty Ai::Tts::Fake.calls, "audio only for what is missing"
    assert episode.reload.review?
  end

  test "rerun of the script keeps number, format and the original brief, then runs everything" do
    script_and_markup(ko_answer(panels: 2))
    episode = Ai::Pipeline.generate(ko_series, panels: 2, brief: "The axe falls", target_words: %w[도끼])

    script_and_markup(ko_answer(panels: 2, title: "다시 · Again"))
    Ai::Pipeline.rerun(episode, "script")

    assert_equal "다시 · Again", episode.reload.title
    user = Ai::Llm::Fake.calls.select { |c| c[:step] == "script" }.last[:messages].last[:content]
    assert_equal "Write episode 1. Target words: 도끼. Brief: The axe falls", user
    assert_equal 2, episode.generation_logs.where(step: "audio").count
  end

  test "a published episode keeps its status when a step is redone" do
    script_and_markup(ko_answer(panels: 2))
    episode = Ai::Pipeline.generate(ko_series, panels: 2)
    episode.publish!

    Ai::Pipeline.rerun(episode, "layout")
    assert episode.reload.published?
    assert_raises(ArgumentError) { Ai::Pipeline.rerun(episode, "script") }
    assert_raises(ArgumentError) { Ai::Pipeline.rerun(episode, "dance") }
  end

  test "jobs run the pipeline" do
    script_and_markup(ko_answer(panels: 2))
    GenerateEpisodeJob.perform_now(ko_series, { "panels" => 2, "format" => "webtoon" })
    episode = ko_series.episodes.sole
    assert episode.review?

    RerunPipelineStepJob.perform_now(episode, "layout")
    assert_equal 2, episode.generation_logs.where(step: "layout").count
  end
end

class GenerateEpisodeJobTest < ActiveSupport::TestCase
  include AiTestHelper
  include ScriptTestHelper
  include SceneTestHelper

  test "count episodes one after another; the brief goes to the first, memory to the next" do
    Ai::Llm::Fake.respond_with(ko_answer(panels: 2), scene_answer(2), { "bubbles" => [] }, { "bubbles" => [] }, { "bubbles" => [] },
                               ko_answer(panels: 2, title: "둘 · Two"), scene_answer(2), { "bubbles" => [] }, { "bubbles" => [] },
                               { "bubbles" => [] })

    episodes = GenerateEpisodeJob.perform_now(ko_series, { "count" => 2, "panels" => 2, "brief" => "The axe falls" })

    assert_equal [ 1, 2 ], episodes.map(&:number)
    scripts = Ai::Llm::Fake.calls.select { |c| c[:step] == "script" }.map { |c| c[:messages] }
    assert_equal "Write episode 1. Brief: The axe falls", scripts[0].last[:content]
    assert_equal "Write episode 2.", scripts[1].last[:content]
    assert_includes scripts[1].first[:content], "Episode 1 «금도끼 · The Golden Axe»: An honest woodcutter loses his axe."
  end
end
