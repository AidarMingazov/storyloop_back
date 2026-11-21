require "test_helper"

class Episodes::ExporterTest < ActiveSupport::TestCase
  MP3 = "ID3\x03\x00\x00\x00\x00\x00\x00 a recorded line".b

  setup do
    @dir = Pathname(Dir.mktmpdir)
    FileUtils.cp(file_fixture("episode_en.json"), @dir.join("01.json"))
    @episode = Episodes::Importer.call(seed, status: "published")
    @series = @episode.series
    @mia = @series.characters.find_by!(key: "mia")
  end

  teardown { FileUtils.rm_rf(@dir) }

  def seed = @dir.join("01.json").read
  def data = JSON.parse(seed)
  def photo(name) = { io: file_fixture("photo.jpg").open, filename: "#{name}.jpg", content_type: "image/jpeg" }
  def recording(name) = { io: StringIO.new(MP3), filename: "#{name}.mp3", content_type: "audio/mpeg" }

  test "voices, sheets, drawn panels and recordings go into the seed JSON and come back on import" do
    @series.update!(narrator_voice: "English_CaptivatingStoryteller")
    @mia.update!(voice: "English_SentimentalLady", appearance_prompt: "auburn hair, mustard-yellow apron")
    @mia.sheet.attach(photo("mia"))
    @episode.panels.first.image.attach(photo("panel-01"))
    @episode.bubbles.first.audio.attach(recording("bubble"))
    lexeme = Lexeme.find_by!(lemma: "run into")
    lexeme.audio.attach(recording("run-into"))

    assert_equal({ "files" => 1, "sheets" => 1, "images" => 1, "recordings" => 1, "words" => 1 }, Episodes::Exporter.call(@series, dir: @dir))

    json = data
    assert_equal "English_CaptivatingStoryteller", json["series"]["narrator_voice"]
    assert_equal({ "key" => "mia", "name" => "Mia", "protagonist" => true, "appearance_prompt" => "auburn hair, mustard-yellow apron",
                   "voice" => "English_SentimentalLady", "sheet" => "media/sheets/mia.jpg" }, json["series"]["characters"].first)
    panel = json["episode"]["panels"].first
    assert_equal %w[image_prompt image layout bubbles], panel.keys
    assert_equal "media/01/panel-01.webp", panel["image"]
    assert_equal "RIFF", @dir.join(panel["image"]).binread(4), "panels are stored as WebP"
    bubble = panel["bubbles"].first
    assert_equal %w[kind character text translation box audio tokens], bubble.keys
    assert_equal MP3, @dir.join(bubble["audio"]).binread
    words = bubble["tokens"].filter_map { |token| token["lemma_audio"] }
    assert_equal 1, words.size
    assert_match %r{\Amedia/words/run-into-\h{8}\.mp3\z}, words.first

    @series.destroy!
    lexeme.audio.purge
    imported = Episodes::Importer.call(seed, status: "published", base_dir: @dir)

    series = imported.series
    assert_equal "English_CaptivatingStoryteller", series.narrator_voice
    mia = series.characters.find_by!(key: "mia")
    assert_equal [ "English_SentimentalLady", "auburn hair, mustard-yellow apron" ], [ mia.voice, mia.appearance_prompt ]
    assert mia.sheet.attached?
    assert_equal "panel-01.webp", imported.panels.first.image.filename.to_s
    assert_equal MP3, imported.bubbles.first.audio.download
    assert_equal MP3, lexeme.reload.audio.download
  end

  test "placeholders and missing recordings stay out; a sheet that is already there is kept on re-import" do
    @mia.sheet.attach(photo("mia"))
    Episodes::Exporter.call(@series, dir: @dir)

    panel = data["episode"]["panels"].first
    assert_not panel.key?("image"), "placeholders are made again on import"
    assert_not panel["bubbles"].first.key?("audio")

    Episodes::Importer.call(seed, base_dir: @dir) # the exported sheet (re-encoded) replaces the original once
    sheet = @mia.reload.sheet.blob
    Episodes::Importer.call(seed, base_dir: @dir)
    assert_equal sheet, @mia.reload.sheet.blob
  end

  test "a text that differs from the database stops the export" do
    @episode.bubbles.first.update!(text: "Guess who I met today!")

    error = assert_raises(Episodes::Exporter::Mismatch) { Episodes::Exporter.call(@series, dir: @dir) }
    assert_match "01.json: panel 1, bubble 1", error.message
    assert_equal file_fixture("episode_en.json").read, seed, "the JSON is left as it was"
  end

  test "a missing media file is reported by the importer" do
    json = data
    json["episode"]["panels"].first["bubbles"].first["audio"] = "media/01/bubble-01-01.mp3"

    error = assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(json, base_dir: @dir) }
    assert_match "panel 1, bubble 1: audio: not found", error.message
    assert_raises(Episodes::Importer::Invalid) { Episodes::Importer.call(json) }
  end
end
