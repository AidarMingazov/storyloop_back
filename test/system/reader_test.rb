require "application_system_test_case"

class ReaderTest < ApplicationSystemTestCase
  def import(name)
    Episodes::Importer.call(file_fixture(name).read, status: "published")
  end

  test "webtoon: tap a phrasal verb, save it, translate a phrase, finish the episode" do
    episode = import("reader_webtoon.json")
    visit episode_path(episode)

    find(".tok", text: "ran into").click
    within ".word-sheet.is-open" do
      assert_text "→ run into"
      assert_text "случайно встретила"
      assert_text "Неожиданная встреча со знакомым."
      click_on "Сохранить слово"
      assert_button "✓ Сохранено"
    end
    assert_selector ".tok.is-saved", text: "ran into"
    assert_equal [ "run into" ], User.last.saved_lexemes.pluck(:lemma)

    find(".tok", text: "By the way").click
    assert_selector ".word-sheet.is-open", text: "Так переходят к новой теме."

    first(".bubble-translate").click
    assert_selector ".word-sheet.is-open", text: "Угадай, кого я сегодня встретила!"

    find("body").send_keys(:escape)
    assert_no_selector ".word-sheet.is-open"

    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    within ".reader-summary" do
      assert_text "Эпизод прочитан"
      assert_selector "[data-summary-new]", text: "2"
      assert_selector "[data-summary-saved]", text: "1"
      # save the second target word right from the summary
      find("[data-summary-lexeme] button[aria-pressed=false]").click
      assert_selector "[data-summary-saved]", text: "2"
    end

    assert_predicate User.last.reading_progresses.find_by(episode: episode), :completed?
  end

  test "chat: messages appear one by one, Korean word shows breakdown, romanization and night mode toggle" do
    episode = import("reader_chat.json")
    visit episode_path(episode)

    assert_selector ".chat-msg", count: 1
    assert_selector ".chat-msg--them", text: "지수 씨, 안녕하세요!"
    click_on "Next ↓"
    assert_selector ".chat-msg--me", text: "오늘 너무 피곤해요!"

    find(".tok", text: "피곤해요").click
    within ".word-sheet.is-open" do
      assert_text "→ 피곤하다"
      assert_text "pigonhaeyo → pigonhada"
      assert_text "피곤하 · stem"
      assert_text "해요체 · polite"
      find("[data-sheet-action=close]").click
    end

    find("[aria-label=Settings]").click
    assert_no_selector ".tok-rt", visible: true
    check "Romanization"
    assert_selector ".tok-rt", text: "pigonhaeyo", visible: true
    check "Night mode"
    assert_selector "html[data-theme=night]"

    click_on "Next ↓"
    assert_text "Episode complete"
    assert_no_button "Next ↓"
  end

  test "progress is restored when coming back to a chat" do
    episode = import("reader_chat.json")
    visit episode_path(episode)
    click_on "Next ↓"
    assert_selector ".chat-msg", count: 2

    visit root_path # leaving the page flushes progress
    visit episode_path(episode)
    assert_selector ".chat-msg", count: 2
  end
end
