require "test_helper"

class Episodes::ImporterTest < ActiveSupport::TestCase
  def json(name) = file_fixture(name).read

  test "imports an English webtoon episode with a phrasal verb as one token" do
    episode = Episodes::Importer.call(json("episode_en.json"), status: "published")

    assert episode.published?
    assert episode.format_webtoon?
    assert_equal "Test Café", episode.series.title
    assert_equal 1, episode.panels.count
    assert episode.panels.first.image.attached?, "webtoon panels get a placeholder image"

    bubble = episode.bubbles.first
    assert_equal "mia", bubble.character.key
    assert_equal({ "x" => 5, "y" => 5, "w" => 60, "h" => 18 }, bubble.box)

    token = bubble.tokens.find_by!(surface: "ran into")
    assert_equal "Guess who I ran into today!"[token.start_offset...token.end_offset], "ran into"
    assert_equal "run into", token.lexeme.lemma
    assert_equal "phrasal_verb", token.lexeme.pos
    assert_equal "случайно встретить", token.lexeme.translation_for("ru")
    assert_equal "случайно встретила", token.context_translation
  end

  test "imports Korean tokens with codepoint offsets, breakdown and politeness" do
    episode = Episodes::Importer.call(json("episode_ko.json"))

    assert episode.review?, "pipeline output lands in review by default"
    assert_not episode.panels.first.image.attached?, "chat panels need no image"

    token = episode.tokens.find_by!(surface: "피곤해요")
    assert_equal [ 8, 12 ], [ token.start_offset, token.end_offset ]
    assert_equal "피곤하다", token.lexeme.lemma
    assert_equal "pigonhada", token.lexeme.romanization
    assert_equal "polite", token.politeness
    assert_equal %w[stem ending], token.breakdown.map { |part| part["role"] }
  end

  test "re-import replaces panels and reuses lexemes" do
    Episodes::Importer.call(json("episode_en.json"))

    assert_no_difference -> { Lexeme.count } do
      assert_no_difference -> { Token.count } do
        Episodes::Importer.call(json("episode_en.json"))
      end
    end
    assert_equal 1, Episode.count
  end

  test "rejects JSON that breaks the schema" do
    data = JSON.parse(json("episode_en.json"))
    data["episode"]["format"] = "comic"

    error = assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(data) }
    assert_match "/episode/format", error.message
    assert_equal 0, Episode.count
  end

  test "rejects explicit offsets that do not match the surface" do
    data = JSON.parse(json("episode_en.json"))
    token = data["episode"]["panels"][0]["bubbles"][0]["tokens"][3]
    token.merge!("start" => 11, "end" => 19) # off by one

    error = assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(data) }
    assert_match "does not match", error.message
    assert_equal 0, Episode.count, "nothing is saved when a token is wrong"
  end

  test "rejects a surface that is not in the text" do
    data = JSON.parse(json("episode_en.json"))
    data["episode"]["panels"][0]["bubbles"][0]["tokens"][3]["surface"] = "run into"

    error = assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(data) }
    assert_match "not found", error.message
  end

  test "rejects an unknown language pair" do
    data = JSON.parse(json("episode_en.json")).merge("language_pair" => "en-ja")

    assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(data) }
  end
end
