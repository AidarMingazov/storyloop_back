require "test_helper"

class StoryLimitsTest < ActiveSupport::TestCase
  test "free generations: guests none, failed ones do not count, admins unlimited" do
    assert_equal 0, users(:guest).story_generations_left
    assert users(:admin).story_generations_left.infinite?

    user = users(:one)
    assert_equal Stories.free_generations, user.story_generations_left

    form = StoryForm.new(user: user, mode: "surprise", pair: "en-ru", rules_accepted: "1")
    request = form.submit
    assert_equal Stories.free_generations - 1, user.story_generations_left

    request.fail!("boom")
    assert_equal Stories.free_generations, user.story_generations_left
  end

  test "the form checks the brief before anything is created (moderation runs in the job)" do
    user = users(:one)
    form = StoryForm.new(user: user, mode: "idea", prompt: "", pair: "en-ru")
    assert_nil form.submit
    assert_equal [ "Напишите идею или вставьте текст", "Нужно согласиться с правилами историй" ], form.errors.map(&:message)

    form = StoryForm.new(user: user, mode: "text", prompt: "x" * 3001, pair: "en-ru", rules_accepted: "1")
    assert_nil form.submit
    assert_equal 0, Series.source_user.count
  end

  test "submit creates the series, episode #1 and the brief; the author name is saved once" do
    user = users(:one)
    request = StoryForm.new(user: user, mode: "theme", theme: "detective", pair: "ko-en", cefr_level: "A2",
                            visibility: "public", display_name: "  Mia  K ", rules_accepted: "1").submit

    series = request.series
    assert series.source_user?
    assert_equal [ user, "public", "pending", "Детектив", "ko-en" ],
                 [ series.author, series.visibility, series.moderation_state, series.title, series.language_pair.code ]
    assert_equal [ 1, "generating", true ], [ request.episode.number, request.episode.status, request.episode.free ]
    assert_equal 12, request.episode.share_token.length
    assert_equal "Mia K", user.reload.display_name
    assert_equal "Mia K", user.author_name
  end
end
