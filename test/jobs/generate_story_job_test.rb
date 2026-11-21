require "test_helper"
require "turbo/broadcastable/test_helper"

class GenerateStoryJobTest < ActiveJob::TestCase
  # turbo-rails adds it to test cases only once Action Cable has loaded, which depends on what ran before
  include Turbo::Broadcastable::TestHelper
  def submit(**attrs)
    StoryForm.new(user: users(:one), mode: "idea", prompt: "A cat detective looks for a lost cake", pair: "en-ru",
                  cefr_level: "A2", rules_accepted: "1", **attrs).submit
  end

  test "the fake generator fills the story from a seed episode and publishes it" do
    request = submit(visibility: "public")
    assert_turbo_stream_broadcasts request, count: 6 do # start, 4 steps, done
      GenerateStoryJob.perform_now(request)
    end

    request.reload
    episode = request.episode.reload
    series = request.series.reload
    assert request.succeeded?
    assert episode.published?
    assert_equal "A cat detective looks for a lost cake", series.title
    assert_not_equal series.title, episode.title # the episode keeps the seed's title
    assert_equal [ 1, "A2", true ], [ episode.number, episode.cefr_level, episode.free ]
    assert episode.panels.any? && episode.tokens.any?
    assert series.approved? && series.published? && series.listed?
    assert_equal %w[script images tokens audio], episode.generation_logs.order(:id).pluck(:step)
    assert_equal 0, episode.cost_usd
    assert_equal %w[story_ready story_published], tracked_events
    assert_equal "idea", tracked("story_ready").sole[:properties][:mode]

    assert_no_difference -> { Panel.count } do
      GenerateStoryJob.perform_now(request) # a repeated job does nothing
    end
  end

  test "text the moderator rejects after generation fails the story and frees the attempt" do
    request = submit
    request.series.update!(title: "Cake #{Stories::FakeModerator::MARKER}") # the generator keeps the story title
    GenerateStoryJob.perform_now(request)

    assert request.reload.failed?
    assert request.episode.reload.failed?
    assert_match "marker", request.error
    assert_not StoryAccess.new(request.episode, users(:guest), via_link: true).readable?
    assert_equal Stories.free_generations, users(:one).story_generations_left
    assert_equal true, tracked("story_failed").sole[:properties][:rejected]
  end

  test "an unexpected error fails the request with the reason for the admin" do
    request = submit
    request.series.update_columns(slug: "Not a slug") # the importer refuses it
    GenerateStoryJob.perform_now(request)

    assert request.reload.failed?
    assert_match "Episodes::Importer::Invalid", request.error
    assert_equal false, tracked("story_failed").sole[:properties][:rejected]
  end
end
