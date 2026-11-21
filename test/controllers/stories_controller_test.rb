require "test_helper"

class StoriesControllerTest < ActionDispatch::IntegrationTest
  test "guests are asked to sign up first and come back to the form" do
    get new_story_path
    assert_response :success
    assert_select "#signup-required"

    post stories_path, params: { story: { mode: "surprise" } }
    assert_redirected_to new_session_path
  end

  test "create: the brief is saved, the job queued, the author lands on the status page" do
    sign_in_as users(:one)
    get new_story_path
    assert_select "input[type=radio][name='story[mode]'][value=surprise]"
    assert_select "#generations-left", "Осталось 3 бесплатные истории"

    assert_enqueued_with(job: GenerateStoryJob) do
      post stories_path, params: { story: { mode: "theme", theme: "school", pair: "en-ru", cefr_level: "A1",
                                            format: "chat", visibility: "link", rules_accepted: "1" } }
    end
    series = Series.source_user.sole
    assert_redirected_to story_path(series)
    event = tracked("story_created").sole[:properties]
    assert_equal [ "theme", "school", "link", 2 ], event.values_at(:mode, :theme, :visibility, :generations_left)

    follow_redirect!
    assert_select "#story-title", "Школа"
    assert_select "[data-status=queued]"
    assert_select "turbo-cable-stream-source"
  end

  test "invalid briefs come back with messages" do
    sign_in_as users(:one)
    post stories_path, params: { story: { mode: "idea", prompt: "", pair: "en-ru", rules_accepted: "1" } }
    assert_response :unprocessable_entity
    assert_select "#story-errors li", "Напишите идею или вставьте текст"
  end

  test "own text can come from a .txt file" do
    sign_in_as users(:one)
    file = Rack::Test::UploadedFile.new(StringIO.new("Once upon a time\nthere was a fox."), "text/plain", original_filename: "fox.txt")
    post stories_path, params: { story: { mode: "text", text_file: file, pair: "en-ru", rules_accepted: "1" } }
    assert_equal "Once upon a time\nthere was a fox.", StoryRequest.sole.prompt
    assert_equal "Once upon a time", Series.source_user.sole.title
  end

  test "when free generations run out: fake door with reason generation" do
    user = users(:one)
    sign_in_as user
    Stories.free_generations.times { StoryForm.new(user: user, mode: "surprise", pair: "en-ru", rules_accepted: "1").submit }

    get new_story_path
    assert_select "#generation-limit"
    assert_equal "generation", tracked("paywall_viewed").sole[:properties][:reason]

    assert_no_enqueued_jobs do
      post stories_path, params: { story: { mode: "surprise", pair: "en-ru", rules_accepted: "1" } }
    end
    assert_response :unprocessable_entity

    post checkout_path, params: { plan: "monthly", reason: "generation" }
    assert_equal [ "generation", "monthly" ], tracked("checkout_clicked").sole[:properties].values_at(:reason, :plan)
  end

  test "my stories: list, visibility, new link, delete; other people's stories are not found" do
    story = create_story(visibility: "link")
    other = create_story(author: users(:admin))
    sign_in_as users(:one)

    get stories_path
    assert_select "#my-stories li", 1
    get story_path(other.series)
    assert_response :not_found

    get story_path(story.series)
    assert_select "#share-link[value*=?]", "/s/#{story.share_token}?ref=#{users(:one).public_id}"

    patch story_path(story.series), params: { visibility: "public" }
    assert story.series.reload.visibility_public?
    assert_equal true, tracked("story_published").sole[:properties][:listed]

    old_token = story.share_token
    post reset_link_story_path(story.series)
    assert_not_equal old_token, story.reload.share_token

    delete story_path(story.series)
    assert_redirected_to stories_path
    assert_not Series.exists?(story.series_id)
  end

  test "banned authors cannot create stories" do
    user = users(:one)
    user.update!(banned_at: Time.current)
    sign_in_as user
    get new_story_path
    assert_redirected_to stories_path
    assert_no_enqueued_jobs do
      post stories_path, params: { story: { mode: "surprise", pair: "en-ru", rules_accepted: "1" } }
    end
  end
end
