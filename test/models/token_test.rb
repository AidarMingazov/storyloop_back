require "test_helper"

class TokenTest < ActiveSupport::TestCase
  setup do
    series = language_pairs(:ko_en).series.create!(slug: "s", title: "S", cefr_level: "A1")
    episode = series.episodes.create!(number: 1, title: "E", format: "chat", cefr_level: "A1")
    panel = episode.panels.create!(position: 0)
    @bubble = panel.bubbles.create!(position: 0, kind: "chat_message", text: "😴 오늘 너무 피곤해요!")
    @lexeme = Lexeme.create!(language: "ko", lemma: "피곤하다", pos: "adjective")
  end

  def build(start, finish, surface)
    @bubble.tokens.build(lexeme: @lexeme, start_offset: start, end_offset: finish, surface: surface,
                         context_translation: "tired")
  end

  test "offsets are codepoints, so emoji before Hangul do not shift them" do
    assert build(8, 12, "피곤해요").valid?
  end

  test "rejects offsets that slice a different string" do
    token = build(7, 11, "피곤해요")

    assert_not token.valid?
    assert_match "does not match", token.errors[:surface].first
  end

  test "end must be after start" do
    assert_not build(8, 8, "").valid?
  end

  test "locate finds surfaces in order" do
    text = "I ran into Sam, then ran into Leo."

    assert_equal [ 2, 10 ], Token.locate(text, "ran into")
    assert_equal [ 21, 29 ], Token.locate(text, "ran into", from: 10)
  end

  test "politeness is one of the Korean speech levels" do
    token = build(8, 12, "피곤해요")
    token.politeness = "rude"

    assert_not token.valid?
  end
end
