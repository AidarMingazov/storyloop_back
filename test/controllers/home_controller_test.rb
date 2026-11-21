require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
  end

  test "new visitors start with onboarding" do
    get root_path
    assert_redirected_to start_path
  end

  test "readers see the library" do
    get episode_path(@episode)
    get root_path
    assert_response :success
    assert_select "h3", "Reader Café"
  end

  test "readers see words due today and where to continue" do
    get episode_path(@episode)
    reader = User.last
    reader.reading_progresses.find_by!(episode: @episode).update!(last_panel_position: 1)
    token = @episode.tokens.first
    reader.user_words.create!(lexeme: token.lexeme, source_token: token)

    get root_path
    assert_select "#due-today", "1 слово к повторению сегодня"
    assert_select "#continue-reading", /Продолжить чтение.*Spilled.*2 из 3/m
    assert_select "#signup-banner", /Сохраните прогресс и слова/
  end
end
