require "test_helper"

class PhotoStoriesControllerTest < ActionDispatch::IntegrationTest
  def photo(type: "image/jpeg") = fixture_file_upload("photo.jpg", type)

  def create_photo_story(**story)
    post stories_path, params: { story: { mode: "photos", photos: [ photo, photo ], photos_consent: "1", pair: "en-ru",
                                          cefr_level: "A1", visibility: "private", rules_accepted: "1", **story } }
    Series.source_user.order(:id).last
  end

  test "photos need consent, 1–10 JPEG/PNG/WebP files; the story is made as a comic" do
    sign_in_as users(:one)
    post stories_path, params: { story: { mode: "photos", photos: [ photo(type: "image/gif") ], pair: "en-ru", rules_accepted: "1" } }
    assert_response :unprocessable_entity
    assert_select "#story-errors li", text: "Фото — только JPEG, PNG или WebP"
    assert_select "#story-errors li", text: "Подтвердите, что эти фото можно использовать"

    post stories_path, params: { story: { mode: "photos", photos: Array.new(11) { photo }, photos_consent: "1", pair: "en-ru", rules_accepted: "1" } }
    assert_select "#story-errors li", text: "Не больше 10 фото"

    assert_enqueued_with(job: GenerateStoryJob) { create_photo_story(format: "chat") }
    request = StoryRequest.last
    assert_equal [ "photos", "webtoon", 2 ], [ request.mode, request.format, request.photos.count ]
    assert request.series.visibility_private?
  end

  test "the author confirms the characters or redraws one; nobody else can" do
    sign_in_as users(:one)
    series = create_photo_story
    request = series.story_requests.sole
    Stories::FakeGenerator.new(step_delay: 0).cast_from_photos(request)
    request.await_confirmation!
    character = series.characters.find_by!(key: "p1")

    get story_path(series)
    assert_select "#story-confirm input[name='names[#{character.id}]'][value=Alex]"
    assert_select "#story-confirm img[alt=Alex]"

    assert_enqueued_with(job: RedrawStorySheetJob, args: [ request, character ]) do
      post redraw_story_path(series), params: { character_id: character.id }
    end
    assert_equal [ 1, "sheets" ], request.reload.values_at(:redraws, :step)
    assert_no_enqueued_jobs(only: GenerateStoryJob) { post confirm_story_path(series), params: { names: { character.id => "Timur" } } }

    request.update!(step: nil)
    assert_enqueued_with(job: GenerateStoryJob, args: [ request ]) do
      post confirm_story_path(series), params: { names: { character.id => "Timur" }, voices: { character.id => "male" } }
    end
    assert_equal [ "Timur", "English_DecentYoungMan" ], character.reload.values_at(:name, :voice)
    assert request.reload.queued? && request.confirmed_at

    request.update!(status: :confirming, redraws: StoryRequest::REDRAWS)
    post redraw_story_path(series), params: { character_id: character.id }
    assert_equal "Перерисовки закончились", flash[:alert]

    sign_in_as users(:admin)
    post confirm_story_path(series)
    assert_response :not_found
  end

  test "photos nobody confirmed for a week: the request fails and the photos go" do
    sign_in_as users(:one)
    request = create_photo_story.story_requests.sole
    request.await_confirmation!

    travel 8.days do
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { ExpireStoryConfirmationsJob.perform_now }
    end

    assert request.reload.failed?
    assert_not request.photos.attached?
    assert_equal Stories.free_generations, users(:one).story_generations_left
  end
end
