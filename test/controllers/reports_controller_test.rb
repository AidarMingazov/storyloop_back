require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "a report takes the story out of the feed until a moderator decides; the link still opens" do
    story = create_story(visibility: "public")
    get shared_episode_path(story.share_token)
    assert_select "#report input[type=radio][value=spam]"

    post episode_reports_path(story), params: { reason: "spam", comment: "ads everywhere" }
    assert_redirected_to community_path
    report = Report.sole
    assert_equal [ "spam", "ads everywhere", "open" ], [ report.reason, report.comment, report.status ]
    assert story.series.reload.pending?
    assert_equal "spam", tracked("story_reported").sole[:properties][:reason]

    get community_path
    assert_select "#community-feed", count: 0
    get shared_episode_path(story.share_token)
    assert_response :success
  end

  test "a report needs a reason; catalog episodes are not reported here" do
    story = create_story(visibility: "public")
    post episode_reports_path(story), params: { reason: "" }
    assert_equal 0, Report.count

    post episode_reports_path(catalog_episode), params: { reason: "spam" }
    assert_response :not_found
  end
end
