require "application_system_test_case"

class FormatsTest < ApplicationSystemTestCase
  def import(name) = Episodes::Importer.call(file_fixture(name).read, status: "published")

  # A horizontal touch swipe across the manga pager, as fractions of its width.
  def swipe(from:, to:)
    execute_script(<<~JS, find(".manga-pager"), from, to)
      const [ el, from, to ] = arguments
      const r = el.getBoundingClientRect(), y = r.top + Math.min(r.height / 2, 200)
      const fire = (type, f) => el.dispatchEvent(new PointerEvent(type, {
        bubbles: true, isPrimary: true, pointerId: 7, pointerType: "touch", button: 0, clientX: r.left + r.width * f, clientY: y }))
      fire("pointerdown", from)
      for (let i = 1; i <= 6; i++) fire("pointermove", from + (to - from) * i / 6)
      fire("pointerup", to)
    JS
  end

  test "manga: pages with a full and two half panels, arrows and keys, finishing on the last page" do
    episode = import("reader_manga.json")
    visit episode_path(episode)

    assert_selector ".manga-counter", text: "1 / 2"
    assert_selector ".manga-page[data-page='1'] .manga-panel--1", count: 2, visible: :all
    find(".tok", text: "ran into").click
    assert_selector ".word-sheet.is-open", text: "случайно встретила"
    find("body").send_keys(:escape) # the card covers the page arrows

    find("[aria-label='Следующая страница']").click
    assert_selector ".manga-counter", text: "2 / 2"
    assert_text "Эпизод прочитан"

    find(".manga-pager").send_keys(:arrow_left)
    assert_selector ".manga-counter", text: "1 / 2"
  end

  test "manga: tap the page edges and swipe to turn; a word tap opens the sheet and the next tap only closes it" do
    episode = import("reader_manga.json")
    visit episode_path(episode)

    assert_selector ".manga-page", count: 1 # the pager shows one page at a time
    tap_at find(".manga-panel"), x: 0.9, y: 0.8
    assert_selector ".manga-counter", text: "2 / 2"
    tap_at first(".manga-panel"), x: 0.1, y: 0.85
    assert_selector ".manga-counter", text: "1 / 2"

    swipe from: 0.8, to: 0.2
    assert_selector ".manga-counter", text: "2 / 2"
    swipe from: 0.2, to: 0.8
    assert_selector ".manga-counter", text: "1 / 2"

    find(".tok", text: "ran into").click
    assert_selector ".word-sheet.is-open"
    tap_at find(".manga-panel"), x: 0.9, y: 0.8
    assert_no_selector ".word-sheet.is-open"
    assert_selector ".manga-counter", text: "1 / 2"
  end

  test "manga: the page turn setting is remembered on the device" do
    episode = import("reader_manga.json")
    visit episode_path(episode)

    find("[aria-label='Настройки']").click
    click_on "Без анимации"
    find("body").send_keys(:escape) # the settings sheet covers the page arrows
    assert_no_selector "#reader-settings.is-open"
    find("[aria-label='Следующая страница']").click
    assert_selector ".manga-counter", text: "2 / 2"

    visit episode_path(episode)
    find("[aria-label='Настройки']").click
    assert_selector "#pref_page_turn_none[aria-pressed=true]"
    click_on "Загиб страницы"
    assert_selector "#pref_page_turn_curl[aria-pressed=true]"
    find("body").send_keys(:escape)
    swipe from: 0.8, to: 0.2
    assert_selector ".manga-counter", text: "2 / 2"
  end

  test "illustrated: paragraphs with speakers and pictures, tap words, translate a paragraph" do
    episode = import("reader_illustrated.json")
    visit episode_path(episode)

    assert_selector ".ill-section", count: 3
    assert_selector ".ill-figure", count: 2
    assert_selector ".ill-p--speech .ill-speaker", text: "LEO"
    find(".tok", text: "By the way").click
    assert_selector ".word-sheet.is-open", text: "Так переходят к новой теме."

    find("body").send_keys(:escape)
    assert_no_selector ".ill-p .bubble-tr" # hidden until asked for
    first(".ill-p [data-translate-bubble]").click
    assert_selector ".ill-p.is-translated .bubble-tr", text: "Угадай, кого я сегодня встретила!"
    assert_no_selector ".word-sheet.is-open"
    first(".ill-p [data-translate-bubble]").click
    assert_no_selector ".ill-p .bubble-tr"

    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    assert_text "Эпизод прочитан"
  end

  test "a line is played from its bubble, next to its translation" do
    episode = import("reader_webtoon.json")
    episode.bubbles.first.audio.attach(io: file_fixture("line.wav").open, filename: "line.wav", content_type: "audio/wav")
    visit episode_path(episode)

    assert_no_selector ".bubble-play" # nothing sits over the art until the bubble is tapped
    bubble = first(".wt-bubble")
    tap_padding bubble
    within(bubble) { find(".bubble-play").click } # plays without opening the card
    assert_no_selector ".word-sheet.is-open"
    assert_selector ".wt-bubble.is-translated", count: 1
  end
end
