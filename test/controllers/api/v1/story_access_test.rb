require "test_helper"

# User stories (wave 7) through the JSON API follow the same StoryAccess rule as the web reader.
class Api::V1::StoryAccessTest < ActionDispatch::IntegrationTest
  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def token_for(email)
    post api_v1_sessions_path, params: { email_address: email, password: "password" }, as: :json
    response.parsed_body["token"]
  end

  def guest_token
    post api_v1_guests_path, params: { language_pair: "en-ru" }, as: :json
    response.parsed_body["token"]
  end

  test "a private story is 404 by id for anyone but its author" do
    story = create_story(visibility: "private")

    get api_v1_episode_path(story)
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
    get api_v1_episode_path(story), headers: auth(guest_token)
    assert_response :not_found
    get api_v1_shared_episode_path(story.share_token)
    assert_response :not_found

    get api_v1_episode_path(story), headers: auth(token_for("one@example.com"))
    assert_response :success
    assert_equal story.id, response.parsed_body["id"]
  end

  test "a link story opens only by its share token, and the old token dies on reset" do
    story = create_story(visibility: "link")

    get api_v1_episode_path(story)
    assert_response :not_found

    get api_v1_shared_episode_path(story.share_token), headers: auth(guest_token)
    assert_response :success
    assert_equal story.id, response.parsed_body["id"]

    old_token = story.share_token
    story.reset_share_token!
    get api_v1_shared_episode_path(old_token)
    assert_response :not_found
    get api_v1_shared_episode_path("nope")
    assert_response :not_found
  end

  test "a public story opens by id; a hidden one or a banned author's does not, even by link" do
    story = create_story(visibility: "public")
    get api_v1_episode_path(story)
    assert_response :success

    story.series.hidden!
    get api_v1_shared_episode_path(story.share_token)
    assert_response :not_found

    story.series.approved!
    users(:one).update!(banned_at: Time.current)
    get api_v1_episode_path(story)
    assert_response :not_found
  end

  test "progress on someone else's private story is refused and not counted as a read" do
    story = create_story(visibility: "private")

    assert_no_difference -> { ReadingProgress.count } do
      patch api_v1_episode_progress_path(story), params: { last_panel_position: 1 }, headers: auth(guest_token), as: :json
    end
    assert_response :not_found
    assert_equal 0, story.reload.reads_count
  end

  test "progress continues on a link story the reader opened through its token" do
    story = create_story(visibility: "link")
    token = guest_token
    get api_v1_shared_episode_path(story.share_token), headers: auth(token)

    patch api_v1_episode_progress_path(story), params: { last_panel_position: 1, completed: true }, headers: auth(token), as: :json
    assert_response :success
    assert_equal({ "last_panel_position" => 1, "completed" => true }, response.parsed_body)
  end
end
