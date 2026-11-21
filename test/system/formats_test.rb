require "application_system_test_case"

class FormatsTest < ApplicationSystemTestCase
  def import(name) = Episodes::Importer.call(file_fixture(name).read, status: "published")

  test "manga: pages with a full and two half panels, arrows and keys, finishing on the last page" do
    episode = import("reader_manga.json")
    visit episode_path(episode)

    assert_selector ".manga-counter", text: "1 / 2"
    assert_selector ".manga-page[data-page='1'] .manga-panel--1", count: 2, visible: :all
    find(".tok", text: "ran into").click
    assert_selector ".word-sheet.is-open", text: "случайно встретила"

    find("[aria-label='Следующая страница']").click
    assert_selector ".manga-counter", text: "2 / 2"
    assert_text "Эпизод прочитан"

    find(".manga-pager").send_keys(:arrow_left)
    assert_selector ".manga-counter", text: "1 / 2"
  end

  test "illustrated: paragraphs with speakers and pictures, tap words, translate a paragraph" do
    episode = import("reader_illustrated.json")
    visit episode_path(episode)

    assert_selector ".ill-section", count: 3
    assert_selector ".ill-figure", count: 2
    assert_selector ".ill-p--speech .ill-speaker", text: "LEO"
    find(".tok", text: "By the way").click
    assert_selector ".word-sheet.is-open", text: "Так переходят к новой теме."

    first(".ill-p [data-translate-bubble]").click
    assert_selector ".word-sheet.is-open", text: "Угадай, кого я сегодня встретила!"

    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    assert_text "Эпизод прочитан"
  end

  test "a bubble with recorded audio gets a listen button" do
    episode = import("reader_webtoon.json")
    episode.bubbles.first.audio.attach(io: file_fixture("line.wav").open, filename: "line.wav", content_type: "audio/wav")
    visit episode_path(episode)

    assert_selector ".bubble-audio", count: 1
    find(".bubble-audio").click # plays without opening the sheet
    assert_no_selector ".word-sheet.is-open"
  end
end
