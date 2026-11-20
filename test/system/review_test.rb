require "application_system_test_case"

class ReviewTest < ApplicationSystemTestCase
  test "save a word while reading, then review it the same day" do
    episode = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    visit episode_path(episode)
    find(".tok", text: "ran into").click
    within(".word-sheet.is-open") { click_on "Сохранить слово" }
    assert_selector ".tok.is-saved", text: "ran into"

    visit root_path
    assert_text "1 слово к повторению сегодня"
    click_on "Повторить"

    assert_selector "mark", text: "ran into"
    click_on "Показать ответ"
    assert_text "run into"
    assert_text "случайно встретить"
    click_on "Легко"

    assert_text "На сегодня всё"
    assert_text "Повторено сегодня: 1"
    assert_operator User.last.user_words.sole.due, :>, 1.day.from_now
  end
end
