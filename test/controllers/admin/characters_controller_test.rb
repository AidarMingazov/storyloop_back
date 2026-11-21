require "test_helper"
require_relative "../../test_helpers/script_test_helper"

class Admin::CharactersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:admin)
    @series = Series.create!(language_pair: language_pairs(:ko_en), slug: "admin-chars", title: "Admin chars", cefr_level: "A1",
                             art_style: "Watercolor.")
    @character = @series.characters.create!(key: "hero", name: "Hero", appearance_prompt: "Woodcutter.")
  end

  test "series form saves tone, art style and narrator voice; the series page shows them" do
    patch admin_series_path(@series), params: { series: { tone: "Warm and funny.", art_style: "Ink and wash.", narrator_voice: "Korean_CalmLady" } }
    assert_redirected_to admin_series_path(@series)
    @series.reload
    assert_equal [ "Warm and funny.", "Ink and wash.", "Korean_CalmLady" ], [ @series.tone, @series.art_style, @series.narrator_voice ]

    get admin_series_path(@series)
    assert_select "p", "Warm and funny."
    assert_select "p", /нет листа персонажа/
  end

  test "character form saves the speech level and an uploaded sheet" do
    sheet = Rack::Test::UploadedFile.new(Rails.root.join("db/templates/ai/series/folk-golden-axe/characters/spirit.jpeg"), "image/jpeg")
    patch admin_character_path(@character), params: { character: { speech_level: "casual", sheet: } }
    assert_redirected_to admin_series_path(@series)
    assert_equal "casual", @character.reload.speech_level
    assert @character.sheet.attached?

    get admin_series_path(@series)
    assert_select "img[alt='Лист персонажа Hero']"
    assert_select "p", /반말/
  end

  test "unknown speech level is rejected" do
    patch admin_character_path(@character), params: { character: { speech_level: "rude" } }
    assert_response :unprocessable_entity
  end

  test "generate sheet enqueues the job; the edit page shows the last generation" do
    assert_enqueued_with(job: GenerateCharacterSheetJob, args: [ @character ]) do
      post generate_sheet_admin_character_path(@character)
    end
    assert_redirected_to edit_admin_character_path(@character)

    perform_enqueued_jobs
    get edit_admin_character_path(@character)
    assert_response :success
    assert_select "#sheet-log", /готово · seedream/
    assert_select "#sheet img[alt='Лист персонажа Hero']"
    assert_select "button", "Перегенерировать"
  end

  test "generate sheet needs an appearance" do
    @character.update!(appearance_prompt: "")
    assert_no_enqueued_jobs { post generate_sheet_admin_character_path(@character) }
    follow_redirect!
    assert_select "#alert", /внешность/
  end
end

class Admin::PipelineControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ScriptTestHelper
  include TokensTestHelper

  setup do
    sign_in_as users(:admin)
    Ai.reset_fakes!
    Ai::Llm::Fake.respond_with(ko_answer(panels: 2))
    @episode = Ai::Steps::Script.call(ko_series, panels: 2)
  end

  test "review screen shows the pipeline with costs, notes and buttons" do
    Ai::Steps::Images.call(@episode, panels: [ @episode.panels.first ])
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("seedream: rejected by the safety filter"))
    Ai::Steps::Images.call(@episode)
    bubble = @episode.bubbles.first
    Ai::Llm::Fake.respond_with({ "bubbles" => [ { "id" => "p1b1", "tokens" => [] } ] }, { "bubbles" => [] }, { "bubbles" => [] })
    Ai::Steps::Tokens.call(@episode, bubbles: [ bubble ])

    get admin_episode_path(@episode)

    assert_response :success
    assert_select "#pipeline tr#step-script td", /попыток: 1/
    assert_select "#pipeline tr#step-images td", "ошибка"
    assert_select "#pipeline tr#step-images td", /нарисовано 1 из 2 · ошибок: 1/
    assert_select "#pipeline tr#step-tokens td", /не размечено: p1b1/
    assert_select "#pipeline tr#step-audio td", "—"
    assert_select "#pipeline form[action='#{rerun_admin_episode_path(@episode, step: 'tokens')}']"
    assert_select ".flash-alert", /Не нарисован: Ai::ContentRejected/
    assert_select ".badge", "не размечено до конца"
  end

  test "buttons enqueue the background work" do
    assert_enqueued_with(job: RerunPipelineStepJob, args: [ @episode, "tokens" ]) do
      post rerun_admin_episode_path(@episode, step: "tokens")
    end
    assert_redirected_to admin_episode_path(@episode)

    panel = @episode.panels.first
    assert_enqueued_with(job: GeneratePanelImageJob, args: [ panel ]) { post redraw_admin_panel_path(panel) }

    bubble = @episode.bubbles.first
    assert_enqueued_with(job: RerunPipelineStepJob, args: [ @episode, "tokens", [ bubble.id ] ]) do
      post markup_admin_bubble_path(bubble)
    end
  end

  test "no rerun while generating or for an unknown step" do
    @episode.update!(status: :generating)
    assert_no_enqueued_jobs { post rerun_admin_episode_path(@episode, step: "images") }
    assert_no_enqueued_jobs { post rerun_admin_episode_path(@episode, step: "dance") }
    get admin_episode_path(@episode)
    assert_select "meta[http-equiv=refresh]"
  end
end

class Admin::GenerateEpisodesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ScriptTestHelper

  setup { sign_in_as users(:admin) }

  test "series templates load from the series list" do
    get admin_series_index_path
    assert_select "#templates form[action='#{load_template_admin_series_index_path(name: 'folk-golden-axe')}']"

    post load_template_admin_series_index_path(name: "folk-golden-axe")
    series = Series.find_by!(slug: "golden-axe")
    assert_redirected_to admin_series_path(series)
    assert_equal 3, series.characters.count

    post load_template_admin_series_index_path(name: "nope")
    assert_redirected_to admin_series_index_path
  end

  test "the generate form enqueues the pipeline for N episodes" do
    get admin_series_path(ko_series)
    assert_select "form#generate"

    assert_enqueued_with(job: GenerateEpisodeJob, args: [ ko_series, { "count" => 2, "format" => "chat", "panels" => 4,
                                                                       "brief" => "A storm", "target_words" => %w[비 바람] } ]) do
      post generate_admin_series_path(ko_series), params: { generation: { count: "2", format: "chat", panels: "4", brief: "A storm", target_words: "비, 바람" } }
    end
    assert_redirected_to admin_series_path(ko_series)

    assert_no_enqueued_jobs do
      post generate_admin_series_path(ko_series), params: { generation: { count: "9", format: "webtoon" } }
    end
  end
end
