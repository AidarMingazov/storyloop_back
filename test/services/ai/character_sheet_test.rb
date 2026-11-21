require "test_helper"
require_relative "../../test_helpers/ai_test_helper"

class Ai::CharacterSheetTest < ActiveSupport::TestCase
  include AiTestHelper

  setup do
    @series = Series.create!(language_pair: language_pairs(:ko_en), slug: "sheet-test", title: "Sheet test", cefr_level: "A1",
                             art_style: "Soft watercolor webtoon.", style_prompt: "Watercolor; misty mountains at dawn.")
    @character = @series.characters.create!(key: "hero", name: "Hero", appearance_prompt: "Young woodcutter,\n  straw sandals.")
  end

  test "prompt uses the drawing style, not the scenery of style_prompt" do
    prompt = Ai::CharacterSheet.new(@character).prompt

    assert prompt.start_with?("Soft watercolor webtoon.\nCharacter model sheet of ONE character, Hero: Young woodcutter, straw sandals.")
    assert_includes prompt, "Four views side by side"
    assert_not_includes prompt, "misty mountains"
  end

  test "prompt falls back to style_prompt without art_style" do
    @series.update!(art_style: "")
    assert Ai::CharacterSheet.new(@character).prompt.start_with?("Watercolor; misty mountains at dawn.")
  end

  test "call generates a 16:9 sheet, attaches it and logs the step" do
    result = Ai::CharacterSheet.call(@character)

    assert_equal 1, result.images.size
    assert_equal [ { step: "sheets", size: "2560x1440", references: 0 } ],
                 Ai::Image::Fake.calls.map { |call| call.slice(:step, :size, :references) }
    assert @character.reload.sheet.attached?
    assert_equal "sheet-test-hero.webp", @character.sheet.filename.to_s

    log = GenerationLog.last
    assert log.succeeded?
    assert_equal "sheets", log.step
    assert_equal 1, log.images
    assert_equal({ "series_id" => @series.id, "character_id" => @character.id, "character" => "hero" },
                 log.metadata.slice("series_id", "character_id", "character"))
    assert_equal [ log ], GenerationLog.for_character(@character).to_a
  end

  test "a rejected prompt fails the log and keeps the old sheet" do
    @character.sheet.attach(io: StringIO.new("old"), filename: "old.webp", content_type: "image/webp")
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("seedream: rejected by the safety filter"))

    assert_raises(Ai::ContentRejected) { Ai::CharacterSheet.call(@character) }
    assert GenerationLog.last.failed?
    assert_equal "old.webp", @character.reload.sheet.filename.to_s
  end

  test "character without appearance is refused before any call" do
    @character.update!(appearance_prompt: " ")
    assert_no_difference -> { GenerationLog.count } do
      assert_raises(ArgumentError) { Ai::CharacterSheet.call(@character) }
    end
    assert_empty Ai::Image::Fake.calls
  end

  test "the job generates the sheet" do
    GenerateCharacterSheetJob.perform_now(@character)
    assert @character.reload.sheet.attached?
  end
end
