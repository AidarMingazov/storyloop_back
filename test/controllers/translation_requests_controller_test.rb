require "test_helper"

class TranslationRequestsControllerTest < ActionDispatch::IntegrationTest
  test "a reader asks for a user story in another pair: one vote, counted in the admin" do
    story = create_story(visibility: "link")
    get shared_episode_path(story.share_token)
    assert_select "#story-translations button", text: /Хочу эту историю/

    post episode_translation_requests_path(story, pair: "ko-en")
    assert_redirected_to shared_episode_path(story.share_token)
    follow_redirect!
    assert_select "#story-notice", text: /Спасибо/
    assert_select "#story-translations button[disabled]", text: /Вы попросили/
    post episode_translation_requests_path(story, pair: "ko-en")
    assert_equal 1, story.translation_requests.count
    assert_equal [ "ko-en" ], tracked("translation_requested").map { |e| e[:properties][:pair] }

    sign_in_as users(:admin)
    get admin_stories_path
    assert_select "#admin-stories td[data-translation-votes]", text: /1/
    get admin_episode_path(story)
    assert_select "#episode-translations", text: /хотят: 1/
    assert_enqueued_with(job: TranslateEpisodeJob, args: [ story, "ko-en" ]) do
      post translate_admin_episode_path(story, pair: "ko-en")
    end
  end

  test "once the translation is out, the button leads to it; catalog episodes and own pairs have no vote" do
    story = create_story(visibility: "public")
    copy = create_story(visibility: "public", pair: "ko-en", fixture: "episode_ko.json")
    copy.update!(origin_episode: story)

    get shared_episode_path(story.share_token)
    assert_select "#story-translations a[href^='/s/#{copy.share_token}']"
    post episode_translation_requests_path(story, pair: "ko-en")
    assert_redirected_to %r{/s/#{copy.share_token}}

    post episode_translation_requests_path(catalog_episode, pair: "ko-en")
    assert_response :not_found
    post episode_translation_requests_path(story, pair: "en-ru")
    assert_response :unprocessable_entity
  end
end
