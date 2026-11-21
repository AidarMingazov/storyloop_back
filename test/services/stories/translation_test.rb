require "test_helper"
require_relative "../../test_helpers/ai_test_helper"
require_relative "../../test_helpers/script_test_helper"

class Stories::TranslationTest < ActiveSupport::TestCase
  include AiTestHelper
  include TokensTestHelper

  KO_WORDS = %w[카페 커피 친구 만나다 미안하다].freeze
  KO_TEXT = "친구를 만나요. 미안해요!".freeze

  def ko_pair = language_pairs(:ko_en)

  # The en-ru fixture story (3 panels × 1 bubble) in Korean for English speakers, panel by panel.
  def translation(panels: 3)
    { "episode" => { "title" => "카페에서 · At the Café", "synopsis" => "Mia meets Leo at a café.", "target_words" => KO_WORDS,
                     "panels" => Array.new(panels) { |i| { "bubbles" => [ { "text" => KO_TEXT, "translation" => "I meet a friend. Sorry! (#{i + 1})" } ] } } } }
  end

  def markup(panels: 3) = { "bubbles" => Array.new(panels) { |i| { "id" => "p#{i + 1}b1", "tokens" => ko_tokens(KO_TEXT) } } }

  test "a user story in another pair: same author and pictures, the text rewritten, words and voices again" do
    story = create_story(visibility: "public")
    scene = { "v" => 1, "setting" => "interior", "place" => "cafe", "time" => "evening", "weather" => "rain", "light" => "warm",
              "mood" => "romantic", "shot" => "medium", "focus" => "mia", "elements" => [ "steam" ] }
    story.panels.first.update!(scene:)
    Ai::Llm::Fake.respond_with(translation(panels: 2), translation, markup) # the first answer drops a panel: fed back

    translated = Stories::Translation.call(story, ko_pair)

    series = translated.series
    assert series.source_user?
    assert_equal [ story.series.author, "public", "pending", "ko-en" ], [ series.author, series.visibility, series.moderation_state, series.language_pair.code ]
    assert_equal [ story, 1, "카페에서 · At the Café", "카페에서 · At the Café" ], [ translated.origin_episode, translated.number, translated.title, series.title ]
    assert_equal story.panels.order(:position).map { |p| p.image.blob }, translated.panels.order(:position).map { |p| p.image.blob }, "the same pictures"
    assert_equal [ scene, {}, {} ], translated.panels.order(:position).map(&:scene), "the same scene tags, no new call"
    assert_not translated.generation_logs.exists?(step: "scene")
    assert_equal %w[leo mia], series.characters.order(:key).pluck(:key)
    assert_equal story.bubbles.map { |b| b.character&.key }, translated.bubbles.map { |b| b.character&.key }, "who says what is kept"
    assert_equal [ KO_TEXT ] * 3, translated.bubbles.map(&:text)
    assert translated.bubbles.all?(&:box)
    assert translated.tokens.any?
    assert translated.bubbles.all? { |b| b.audio.attached? }

    assert_includes Ai::Llm::Fake.calls[1][:messages].last[:content], "2 panels, the original has 3"
    prompt = Ai::Llm::Fake.calls.first[:messages].map { |m| m[:content] }.join("\n")
    assert_includes prompt, "The original is written in English"
    assert_includes prompt, story.bubbles.first.text
    assert_equal story.id, translated.generation_logs.find_by!(step: "script").metadata["translation_of"]
  end

  test "TranslateEpisodeJob: a user story is published after moderation, a catalog episode waits for review" do
    story = create_story(visibility: "public")
    Ai::Llm::Fake.respond_with(translation, markup)
    TranslateEpisodeJob.perform_now(story, "ko-en")
    copy = Stories::Translation.existing(story, ko_pair)
    assert copy.published?
    assert copy.series.approved? && copy.series.published? && copy.series.listed?

    assert_no_difference -> { Episode.count } do
      TranslateEpisodeJob.perform_now(story, "ko-en") # already translated
    end

    Ai::Llm::Fake.respond_with(translation, markup)
    TranslateEpisodeJob.perform_now(catalog_episode, "ko-en")
    copy = Stories::Translation.existing(catalog_episode, ko_pair)
    assert copy.review?
    assert_equal [ catalog_episode.series.slug, "catalog", catalog_episode.number ], [ copy.series.slug, copy.series.source, copy.number ]
  end

  test "an episode is not translated into its own pair" do
    assert_raises(ArgumentError) { Stories::Translation.new(create_story, language_pairs(:en_ru)) }
  end
end
