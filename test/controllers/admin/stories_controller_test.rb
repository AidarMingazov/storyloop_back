require "test_helper"

class Admin::StoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @story = create_story(visibility: "public")
    @report = Report.create!(reporter: users(:guest), episode: @story, reason: "hate")
  end

  test "only admins" do
    sign_in_as users(:one)
    get admin_stories_path
    assert_response :not_found
  end

  test "the queue shows open reports; hide closes them and removes the story for everyone" do
    sign_in_as users(:admin)
    get admin_reports_path
    assert_select "#report-queue section", 1
    get admin_stories_path
    assert_select "#admin-stories tbody tr", 1

    post hide_admin_story_path(@story.series)
    assert @story.series.reload.hidden?
    assert @report.reload.resolved?
    assert_equal users(:admin), @report.resolved_by
    get admin_reports_path
    assert_select "#reports-empty"
    assert_not StoryAccess.new(@story, users(:guest), via_link: true).readable?
  end

  test "approve brings a reported story back to the feed" do
    sign_in_as users(:admin)
    assert @story.series.reload.pending?
    post approve_admin_story_path(@story.series)
    assert @story.series.reload.listed?
    assert @report.reload.dismissed?
  end

  test "ban the author: their stories disappear for others, no new stories" do
    sign_in_as users(:admin)
    post ban_author_admin_story_path(@story.series)
    author = users(:one).reload
    assert author.banned?
    assert_not StoryAccess.new(@story, users(:guest)).readable?
    assert_equal 0, author.story_generations_left
  end
end
