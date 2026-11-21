require "application_system_test_case"

class ReaderTest < ApplicationSystemTestCase
  def import(name)
    Episodes::Importer.call(file_fixture(name).read, status: "published")
  end

  test "webtoon: tap a phrasal verb, save it, translate a line, finish the episode" do
    episode = import("reader_webtoon.json")
    visit episode_path(episode)

    find(".tok", text: "ran into").click
    within ".word-sheet.is-open" do
      assert_selector ".wc-dict", text: "run into" # the dictionary form of "ran into"
      assert_text "случайно встретила"
      assert_text "Неожиданная встреча со знакомым."
      click_on "Сохранить слово"
      assert_button "Сохранено"
      assert_selector "[data-sheet-action=save] use[href='#i-bookmark-fill']", visible: :all
    end
    assert_selector ".tok.is-saved", text: "ran into"
    assert_equal [ "run into" ], User.last.saved_lexemes.pluck(:lemma)

    find(".tok", text: "By the way").click
    assert_selector ".word-sheet.is-open", text: "Так переходят к новой теме."

    find("body").send_keys(:escape)
    assert_no_selector ".word-sheet.is-open"

    # A tap on the bubble outside its words shows the line's translation inside the bubble, and hides it again.
    execute_script "window.scrollTo(0, 0)"
    bubble = first(".wt-bubble")
    assert_no_selector ".bubble-tr"
    tap_padding bubble
    within(bubble) { assert_selector ".bubble-tr", text: "Угадай, кого я сегодня встретила!" }
    assert_no_selector ".word-sheet.is-open"
    tap_padding bubble
    assert_no_selector ".bubble-tr"

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

  test "chat: messages appear one by one, Korean word shows breakdown, romanization and Midnight" do
    episode = import("reader_chat.json")
    visit episode_path(episode)

    assert_selector ".chat-msg", count: 1
    assert_selector ".chat-msg--them", text: "지수 씨, 안녕하세요!"
    click_on "Next"
    assert_selector ".chat-msg--me", text: "오늘 너무 피곤해요!"

    find(".tok", text: "피곤해요").click
    within ".word-sheet.is-open" do
      assert_selector ".wc-rom", text: "pigonhaeyo"
      assert_selector ".wc-dict", text: "피곤하다 pigonhada"
      assert_selector ".wc-gram li", text: "피곤하"
      assert_selector ".tag", text: "해요체 · polite"
      find("[data-sheet-action=close]").click
    end
    assert_no_selector ".word-sheet.is-open"

    assert_no_selector ".tok-rt", visible: true
    find("[aria-label=Settings]").click
    within "#reader-settings.is-open" do
      assert_text "Korean · A1"
      assert_no_selector "#story-editions" # this story exists in one language
      click_on "Romanization"
      assert_selector "#pref_romanization[aria-checked=true]"
      click_on "Midnight"
    end
    assert_selector ".tok-rt", text: "pigonhaeyo", visible: true
    assert_selector "html[data-theme=night]"
    find("body").send_keys(:escape) # the settings sheet covers the Next button
    assert_no_selector "#reader-settings.is-open"

    click_on "Next"
    assert_text "Episode complete"
    assert_no_button "Next"
  end

  test "a registered reader's summary has no signup block and no stray text" do
    episode = import("reader_webtoon.json")
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address # the browser asks for English before sign-in
    fill_in "password", with: "password"
    find("form input[type=submit]").click
    assert_no_current_path new_session_path

    visit episode_path(episode)
    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    within ".reader-summary" do
      assert_selector "[data-summary-new]", text: "2"
      assert_no_selector "[data-summary-signup]"
      assert_no_text "null"
    end
  end

  test "progress is restored when coming back to a chat" do
    episode = import("reader_chat.json")
    visit episode_path(episode)
    click_on "Next"
    assert_selector ".chat-msg", count: 2

    visit root_path # leaving the page flushes progress
    visit episode_path(episode)
    assert_selector ".chat-msg", count: 2
  end

  test "webtoon: the header hides on the way down and comes back on the way up or on a tap on the picture" do
    episode = import("reader_webtoon.json")
    visit episode_path(episode)
    assert_selector ".reader-pill", text: "EN · A2"

    assert_no_selector ".reader.chrome-off"
    execute_script "window.scrollTo(0, 400)"
    assert_selector ".reader.chrome-off"
    execute_script "window.scrollTo(0, 320)"
    assert_no_selector ".reader.chrome-off"

    execute_script "window.scrollTo(0, 0)"
    tap_at first(".wt-panel"), x: 0.5, y: 0.9 # the picture, away from the bubble
    assert_selector ".reader.chrome-off"
    tap_at first(".wt-panel"), x: 0.5, y: 0.9
    assert_no_selector ".reader.chrome-off"
  end

  test "the word card keeps its line above the sheet and closes when the reader scrolls on" do
    episode = import("reader_webtoon.json")
    visit episode_path(episode)

    find(".tok", text: "By the way").click
    assert_selector ".word-sheet.is-open"
    above = evaluate_script(<<~JS)
      document.querySelector(".tok.is-active").closest(".wt-bubble").getBoundingClientRect().bottom <=
        document.querySelector(".word-sheet").getBoundingClientRect().top
    JS
    assert above, "the bubble of the tapped word is not under the sheet"

    execute_script "window.scrollBy(0, 200)"
    assert_no_selector ".word-sheet.is-open"
    assert_no_selector ".tok.is-active"
  end

  test "settings: translations under every line, text size and theme are remembered on the device" do
    episode = import("reader_webtoon.json")
    visit episode_path(episode)
    assert_no_selector ".bubble-tr"

    find("[aria-label='Настройки']").click
    within "#reader-settings.is-open" do
      assert_text "Английский · A2"
      assert_selector "#pref_theme_auto[aria-pressed=true]"
      click_on "Перевод под каждой репликой"
      click_on "Крупный"
      click_on "Полночь"
    end
    assert_selector ".wt-bubble .bubble-tr", count: 3
    assert_selector ".reader[data-size=l]"
    assert_selector "html[data-theme=night]"

    tap_at first(".wt-panel"), x: 0.85, y: 0.55 # a tap on the picture, above the sheet, closes the settings
    assert_no_selector "#reader-settings.is-open"
    assert_no_selector ".reader.chrome-off" # …and only that

    visit episode_path(episode)
    assert_selector "html[data-theme=night]"
    assert_selector ".reader[data-size=l][data-translations=on]"
    assert_selector ".wt-bubble .bubble-tr", count: 3
  end

  test "desktop: the word card is a popover under its line, pointing at the word; S saves, Esc closes" do
    episode = import("reader_webtoon.json")
    at_desktop do
      visit episode_path(episode)
      find(".tok", text: "ran into").click
      assert_selector ".word-sheet.is-open.is-popover", text: "случайно встретила"
      at_word = evaluate_script(<<~JS)
        (() => {
          const token = document.querySelector(".tok.is-active")
          const word = token.getBoundingClientRect(), line = token.closest(".wt-bubble").getBoundingClientRect()
          const card = document.querySelector(".word-sheet").getBoundingClientRect()
          const gap = card.top >= line.bottom ? card.top - line.bottom : line.top - card.bottom
          const centre = word.left + word.width / 2
          return Math.abs(gap - 12) < 3 && card.left <= centre && card.right >= centre
        })()
      JS
      assert at_word, "the popover sits 12px from the bubble, not over it, and spans the word's centre"

      find("body").send_keys("s")
      assert_selector ".word-sheet [data-sheet-action=save][aria-pressed=true]"
      assert_selector ".tok.is-saved", text: "ran into"

      execute_script "window.scrollBy(0, 220)" # a popover scrolls with its word instead of closing
      assert_selector ".word-sheet.is-open.is-popover"
      find("body").send_keys(:escape)
      assert_no_selector ".word-sheet.is-open"
    end
  end
end
