require "test_helper"

class EpisodePayloadTest < ActiveSupport::TestCase
  setup do
    @en = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    @ko = Episodes::Importer.call(file_fixture("episode_ko.json").read, status: "published")
  end

  test "describes panels, bubbles and tokens with codepoint offsets" do
    json = EpisodePayload.new(@en).as_json

    assert_equal "webtoon", json[:format]
    assert_equal({ code: "en-ru", target_lang: "en", native_lang: "ru" }, json[:language_pair])
    panel = json[:panels].first
    assert_match %r{\A/rails/active_storage/representations/}, panel[:image_url]
    assert_equal 0.8, panel[:aspect_ratio]

    bubble = panel[:bubbles].first
    token = bubble[:tokens].find { |t| t[:surface] == "ran into" }
    assert_equal "ran into", bubble[:text][token[:start]...token[:end]]
    assert_equal "run into", json[:lexemes][token[:lexeme_id]][:lemma]
    assert_equal "случайно встретить", json[:lexemes][token[:lexeme_id]][:translation]
    assert_nil json[:user], "no user section without a reader"
  end

  test "Korean tokens carry romanization, breakdown and politeness" do
    token = EpisodePayload.new(@ko).as_json[:panels].first[:bubbles].first[:tokens].last

    assert_equal "pigonhaeyo", token[:romanization]
    assert_equal "polite", token[:politeness]
    assert_equal "stem", token[:breakdown].first["role"]
  end

  test "lexemes are deduplicated across tokens" do
    json = EpisodePayload.new(@en).as_json
    lexeme_ids = json[:panels].flat_map { |p| p[:bubbles].flat_map { |b| b[:tokens].map { |t| t[:lexeme_id] } } }

    assert_equal lexeme_ids.uniq.sort, json[:lexemes].keys.sort
  end

  test "user section has saved words and progress" do
    user = users(:guest)
    lexeme = @en.tokens.find_by!(surface: "ran into").lexeme
    user.user_words.create!(lexeme: lexeme)
    user.reading_progresses.create!(episode: @en, last_panel_position: 0, completed_at: Time.current)

    json = EpisodePayload.new(@en, user: user).as_json

    assert_equal [ lexeme.id ], json[:user][:saved_lexeme_ids]
    assert json[:user][:completed]
  end

  test "next episode is marked locked when the reader cannot open it" do
    data = JSON.parse(file_fixture("episode_en.json").read)
    data["episode"].merge!("number" => 2, "title" => "Paid", "free" => false)
    Episodes::Importer.call(data, status: "published")

    assert EpisodePayload.new(@en, user: users(:guest)).as_json[:next_episode][:locked]
    assert_not EpisodePayload.new(@en, user: users(:admin)).as_json[:next_episode][:locked]
  end
end
