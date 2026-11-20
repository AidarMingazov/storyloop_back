require "test_helper"

class ReadingProgressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    get episode_path(@episode)
    @user = User.last
  end

  test "keeps the furthest position and marks completion once" do
    patch episode_progress_path(@episode), params: { last_panel_position: 3 }, as: :json
    patch episode_progress_path(@episode), params: { last_panel_position: 1 }, as: :json
    assert_response :no_content

    progress = @user.reading_progresses.find_by!(episode: @episode)
    assert_equal 3, progress.last_panel_position
    assert_not progress.completed?

    patch episode_progress_path(@episode), params: { last_panel_position: 3, completed: true }, as: :json
    first_completion = progress.reload.completed_at
    assert first_completion

    patch episode_progress_path(@episode), params: { last_panel_position: 3, completed: true }, as: :json
    assert_equal first_completion, progress.reload.completed_at
  end
end
