require "test_helper"

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
