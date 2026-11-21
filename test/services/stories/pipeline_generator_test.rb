require "test_helper"
require "turbo/broadcastable/test_helper"
require_relative "../../test_helpers/ai_test_helper"
require_relative "../../test_helpers/script_test_helper"

class Stories::PipelineGeneratorTest < ActiveSupport::TestCase
  include AiTestHelper
  include TokensTestHelper
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  def submit(**attrs)
    StoryForm.new(user: users(:one), mode: "idea", prompt: "Masha bakes a cake for Jim's birthday and burns it", pair: "en-ru",
                  cefr_level: "A2", cast: "classic", rules_accepted: "1", **attrs).submit
  end

  # A story that passes Ai::ScriptCheck for the classic cast (della, jim); Della is renamed after the brief.
  def story_answer(panels: 6, cast: { "della" => "Masha" })
    { "cast" => cast, "episode" => {
      "title" => "The Burnt Cake", "synopsis" => "Masha burns a birthday cake. Jim loves it anyway.",
      "target_words" => [ "bake", "burn", "birthday", "smell", "surprise", "anyway" ],
      "panels" => Array.new(panels) do |i|
        { "image_prompt" => "Medium shot: Masha in a small kitchen with Jim, moment #{i + 1}.",
          "bubbles" => [
            { "kind" => "narration", "character" => nil, "text" => "Masha wants to bake a birthday cake.", "translation" => "Маша хочет испечь торт." },
            { "kind" => "speech", "character" => "jim", "text" => "What is that smell? I love it anyway!", "translation" => "Что за запах? Мне всё равно нравится!" }
          ] }
      end
    } }
  end

  # The script, then the markup of every bubble (Ai::Steps::Tokens asks for 10 bubbles at a time).
  def script_and_markup(answer)
    ids = answer["episode"]["panels"].each_with_index.flat_map do |panel, p|
      panel["bubbles"].each_with_index.map { |bubble, b| [ "p#{p + 1}b#{b + 1}", bubble["text"] ] }
    end
    markup = ids.each_slice(Ai::Steps::Tokens::CHUNK).map do |chunk|
      { "bubbles" => chunk.map { |id, text| { "id" => id, "tokens" => en_tokens(text) } } }
    end
    Ai::Llm::Fake.respond_with(answer, *markup)
  end

  test "the cast, a complete story from the brief, every pipeline step; the episode is published" do
    request = submit
    script_and_markup(story_answer)

    assert_turbo_stream_broadcasts request, count: 5 do # script, images, layout, tokens, audio
      Stories::PipelineGenerator.new.call(request)
    end

    episode = request.episode.reload
    series = request.series.reload
    assert episode.published? && series.published?
    assert_equal [ "The Burnt Cake" ] * 2, [ series.title, episode.title ]
    assert_equal [ 1, true, "A2", 6 ], [ episode.number, episode.free, episode.cefr_level, episode.panels.count ]
    assert episode.panels.none?(&:placeholder_image?)
    assert episode.bubbles.all?(&:box)
    assert episode.tokens.any?
    assert episode.bubbles.all? { |b| b.audio.attached? }
    assert_equal %w[script] + %w[images] * 6 + %w[layout tokens audio], episode.generation_logs.order(:id).pluck(:step)

    della = series.characters.find_by!(key: "della")
    assert_equal "Masha", della.name, "named after the brief"
    assert della.sheet.attached?
    assert_equal [ 2 ] * 6, Ai::Image::Fake.calls.map { |call| call[:references] }, "sheets of Masha (renamed Della) and Jim"
    assert_equal "English_CaptivatingStoryteller", series.narrator_voice

    prompt = Ai::Llm::Fake.calls.first[:messages].map { |m| m[:content] }.join("\n")
    assert_includes prompt, "ONE complete story"
    assert_includes prompt, "Masha bakes a cake for Jim's birthday"
    assert_includes prompt, "della = Della (protagonist)"
  end

  test "names the brief cannot give are ignored; the cast keeps its own" do
    request = submit
    script_and_markup(story_answer(cast: { "della" => "<script>", "jim" => "Della", "nobody" => "Ann" }))

    Stories::PipelineGenerator.new.call(request)

    assert_equal %w[Della Jim], request.series.characters.where(key: %w[della jim]).order(:key).pluck(:name)
  end

  test "a picture the provider refuses rejects the story; a failed one is drawn again" do
    request = submit
    script_and_markup(story_answer(panels: 4))
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("sensitive content", provider: "seedream"))
    assert_raises(Stories::Rejected) { Stories::PipelineGenerator.new.call(request) }

    other = submit
    script_and_markup(story_answer(panels: 4))
    Ai::Image::Fake.reset!
    Ai::Image::Fake.respond_with(Ai::ProviderError.new("timeout", provider: "seedream"))
    Stories::PipelineGenerator.new.call(other)
    assert other.episode.reload.panels.none?(&:placeholder_image?)
    assert_equal 5, Ai::Image::Fake.calls.size, "4 panels + 1 redrawn"
  end

  test "GenerateStoryJob with STORY_GENERATOR=pipeline: ready, published, costs logged" do
    Rails.configuration.x.stories.generator = "pipeline"
    request = submit(visibility: "public")
    script_and_markup(story_answer)

    GenerateStoryJob.perform_now(request)

    assert request.reload.succeeded?, request.error
    assert request.series.reload.listed?
    assert_equal %w[story_ready story_published], tracked_events
  ensure
    Rails.configuration.x.stories.generator = "fake"
  end
end
