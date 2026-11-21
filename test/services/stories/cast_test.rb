require "test_helper"

class Stories::CastTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  def user_series(pair: :ko_en)
    Series.create!(source: :user, author: users(:one), language_pair: language_pairs(pair), slug: "u-#{SecureRandom.hex(4)}",
                   title: "Draft", cefr_level: "A1", moderation_state: :pending)
  end

  test "every theme card has a cast, and every cast is complete for both target languages" do
    Stories::Themes.keys.each { |theme| assert Stories::Cast.for_theme(theme), "no cast for theme #{theme}" }

    Stories::Cast.all.each do |cast|
      assert cast.title(:ru).present? && cast.title(:en).present?, cast.key
      assert cast.data["art_style"].present? && cast.data["style_prompt"].to_s.include?("No text"), cast.key
      assert_equal 1, cast.characters.count { |c| c["protagonist"] }, "#{cast.key}: one protagonist"
      cast.characters.each do |c|
        where = "#{cast.key}/#{c['key']}"
        assert_match(/\A[a-z0-9_]+\z/, c["key"], where)
        %w[ko en].each do |lang|
          assert cast.name_for(c, lang).match?(Stories::Script::NAME), "#{where}: #{lang} name"
          assert c.dig("voice", lang).present?, "#{where}: #{lang} voice"
        end
        assert c["appearance_prompt"].present?, where
        assert c["sheet"].to_s.start_with?("casts/#{cast.key}/", "series/"), "#{where}: sheet path"
      end
    end
  end

  test "the cast of a request: picked, else the theme's, random for surprise, everyday otherwise" do
    assert_equal "detective", Stories::Cast.for(mode: "idea", cast: "detective").key
    assert_equal "school", Stories::Cast.for(mode: "theme", theme: "school").key
    assert_equal "folk", Stories::Cast.for(mode: "theme", theme: "folk-tale", cast: "").key
    assert_includes Stories::Cast.keys, Stories::Cast.for(mode: "surprise", random: Random.new(1)).key
    assert_equal "cafe", Stories::Cast.for(mode: "text").key
    assert_equal "cafe", Stories::Cast.for(mode: "idea", cast: "nope").key
  end

  test "cast_into copies style, names and voices of the story's language and shares the sheets" do
    cast = Stories::Cast.fetch("office")
    ko = cast.cast_into(user_series(pair: :ko_en))
    en = cast.cast_into(user_series(pair: :en_ru))

    assert_equal cast.data["style_prompt"], ko.style_prompt
    assert_equal [ "Korean_CalmLady", "English_CaptivatingStoryteller" ], [ ko.narrator_voice, en.narrator_voice ]
    seoyeon_ko, seoyeon_en = [ ko, en ].map { |series| series.characters.find_by!(key: "seoyeon") }
    assert_equal [ "Seoyeon", "Sophie" ], [ seoyeon_ko.name, seoyeon_en.name ]
    assert_equal [ "Korean_SweetGirl", "English_SentimentalLady" ], [ seoyeon_ko.voice, seoyeon_en.voice ]
    assert seoyeon_ko.protagonist?
    assert_equal "polite", ko.characters.find_by!(key: "dohyun").speech_level
    assert_nil en.characters.find_by!(key: "dohyun").speech_level, "speech levels are Korean only"

    assert seoyeon_ko.sheet.attached?
    assert_equal seoyeon_ko.sheet.blob, seoyeon_en.sheet.blob, "one blob per sheet, attached to every copy"

    assert_no_difference -> { ko.characters.count } do
      assert_no_difference -> { ActiveStorage::Blob.count } do
        cast.cast_into(ko.reload)
      end
    end
  end

  test "deleting one story keeps the shared sheet of the others" do
    cast = Stories::Cast.fetch("classic")
    first = cast.cast_into(user_series)
    second = cast.cast_into(user_series)
    blob = second.characters.find_by!(key: "della").sheet.blob

    perform_enqueued_jobs { first.destroy! }

    assert ActiveStorage::Blob.exists?(blob.id)
    assert second.characters.find_by!(key: "della").sheet.attached?
  end
end
