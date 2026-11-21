require "test_helper"

class Ai::SeriesTemplateTest < ActiveSupport::TestCase
  test "every template in db/templates/ai/series loads with valid characters" do
    assert_includes Ai::SeriesTemplate.names, "folk-golden-axe"
    Ai::SeriesTemplate.names.each do |name|
      data = Ai::SeriesTemplate.new(name).data.fetch("series")
      assert data["tone"].present?, "#{name}: tone"
      assert data["art_style"].present?, "#{name}: art_style"
      assert data["narrator_voice"].present?, "#{name}: narrator_voice"
      voices = data["characters"].map { |c| c["voice"] }
      assert_not_includes voices, data["narrator_voice"], "#{name}: narrator must not share a character's voice"
      data["characters"].each do |c|
        assert c["speech_level"].nil? || Character::SPEECH_LEVELS.include?(c["speech_level"]), "#{name}/#{c['key']}"
      end
    end
  end

  test "load creates the series, characters and attaches sheets from the template folder" do
    series = Ai::SeriesTemplate.load("folk-golden-axe")

    assert series.draft?
    assert_equal "ko-en", series.language_pair.code
    assert_equal "golden-axe", series.slug
    assert_match(/honesty is rewarded/, series.tone)
    assert_match(/watercolor/, series.art_style)
    assert_match(/No text/, series.style_prompt)
    assert_equal "Korean_CalmLady", series.narrator_voice

    woodcutter, spirit, neighbor = series.characters.order(:id).to_a
    assert_equal %w[woodcutter spirit neighbor], [ woodcutter, spirit, neighbor ].map(&:key)
    assert woodcutter.protagonist?
    assert_not spirit.protagonist?
    assert_equal %w[polite casual polite], [ woodcutter, spirit, neighbor ].map(&:speech_level)
    assert_equal "Korean_WiseTeacher", spirit.voice
    assert woodcutter.sheet.attached?
    assert_equal "image/jpeg", woodcutter.sheet.content_type
    assert_equal "golden-axe-woodcutter.jpeg", woodcutter.sheet.filename.to_s
  end

  test "reloading updates in place and keeps a sheet regenerated in the admin unless replace_sheets" do
    series = Ai::SeriesTemplate.load("folk-golden-axe")
    spirit = series.characters.find_by!(key: "spirit")
    spirit.update!(voice: "Korean_Other", speech_level: "formal")
    spirit.sheet.attach(io: StringIO.new(Episodes::PlaceholderImage.render(1.6, 1)), filename: "mine.webp", content_type: "image/webp")

    assert_no_difference -> { Series.count } do
      assert_no_difference -> { Character.count } do
        Ai::SeriesTemplate.load("folk-golden-axe")
      end
    end
    spirit.reload
    assert_equal "Korean_WiseTeacher", spirit.voice
    assert_equal "casual", spirit.speech_level
    assert_equal "mine.webp", spirit.sheet.filename.to_s

    Ai::SeriesTemplate.load("folk-golden-axe", replace_sheets: true)
    assert_equal "golden-axe-spirit.jpeg", spirit.reload.sheet.filename.to_s
  end

  test "re-importing an episode of the series keeps the pipeline-only fields" do
    series = Ai::SeriesTemplate.load("folk-golden-axe")
    data = JSON.parse(file_fixture("episode_ko.json").read)
    data["series"]["slug"] = "golden-axe"

    Episodes::Importer.call(data)

    series.reload
    assert_match(/honesty is rewarded/, series.tone)
    assert_match(/watercolor/, series.art_style)
    assert_equal "Korean_CalmLady", series.narrator_voice
    woodcutter = series.characters.find_by!(key: "woodcutter")
    assert_equal "polite", woodcutter.speech_level
    assert woodcutter.sheet.attached?
  end

  test "unknown template names the known ones" do
    error = assert_raises(ArgumentError) { Ai::SeriesTemplate.new("nope") }
    assert_match(/folk-golden-axe/, error.message)
  end
end
