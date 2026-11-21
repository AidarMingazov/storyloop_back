require "test_helper"
require_relative "../../test_helpers/ai_test_helper"
require_relative "../../test_helpers/script_test_helper"

class Stories::PhotoCastTest < ActiveSupport::TestCase
  include AiTestHelper
  include TokensTestHelper
  include ActiveJob::TestHelper

  def photo = Rack::Test::UploadedFile.new(file_fixture("photo.jpg"), "image/jpeg")

  def submit(photos: 2, **attrs)
    StoryForm.new(user: users(:one), mode: "photos", photos: Array.new(photos) { photo }, photos_consent: "1",
                  prompt: "Our weekend at the beach", pair: "en-ru", cefr_level: "A2", visibility: "private",
                  rules_accepted: "1", **attrs).submit
  end

  def vision(safety: {}, subjects: nil)
    { "safety" => { "minors" => false, "nudity" => false, "violence" => false, "public_figure" => false }.merge(safety),
      "subjects" => subjects || [
        { "photos" => [ 1, 2 ], "best_photo" => 2, "kind" => "person", "voice" => "male", "look" => "adult man, short black hair, round glasses", "outfit" => "white linen shirt" },
        { "photos" => [ 1 ], "best_photo" => 1, "kind" => "animal", "voice" => "female", "look" => "small fluffy white dog", "outfit" => "red collar" }
      ],
      "places" => [ { "photo" => 1, "description" => "a beach bar with straw umbrellas at sunset" } ],
      "scenes" => [ "photo 1: a man and his dog at a beach bar", "photo 2: the man laughs on a wakeboard" ],
      "story_hooks" => [ "the dog steals a snack", "first time on a wakeboard" ] }
  end

  test "the vision model sees the photos; people and animals become characters with sheets drawn after their best photo" do
    request = submit
    Ai::Llm::Fake.respond_with(vision)

    Stories::PhotoCast.call(request)

    call = Ai::Llm::Fake.calls.sole
    assert_equal [ "vision", 2 ], [ call[:step], call[:images] ]
    assert_includes call[:messages].first[:content], "never name anyone"

    series = request.series.reload
    man, dog = series.characters.order(:key).to_a
    assert_equal [ "p1", "Alex", true, "English_DecentYoungMan" ], [ man.key, man.name, man.protagonist, man.voice ]
    assert_equal [ "p2", "Buddy", false, "English_SentimentalLady" ], [ dog.key, dog.name, dog.protagonist, dog.voice ]
    assert_equal "adult man, short black hair, round glasses; white linen shirt", man.appearance_prompt
    assert man.sheet.attached? && dog.sheet.attached?

    sheets = Ai::Image::Fake.calls
    assert_equal [ "photo_sheets" ] * 2, sheets.map { |c| c[:step] }
    assert_equal [ 1, 1 ], sheets.map { |c| c[:references] }
    assert sheets.all? { |c| c[:prompt].include?("NOT photorealistic") }

    assert_includes series.style_prompt, "Settings from the learner's photos: a beach bar with straw umbrellas at sunset."
    assert_equal Stories::Cast.fetch("cafe").data["art_style"], series.art_style
    assert_equal vision["scenes"], request.reload.vision["scenes"]
    assert_equal %w[vision sheets sheets], request.episode.generation_logs.order(:id).pluck(:step)
    assert_equal "succeeded", request.episode.generation_logs.find_by!(step: "vision").status
  end

  test "children, nudity, violence or a famous person in the photos reject the story" do
    { "minors" => "minors", "nudity" => "sexual", "public_figure" => "personal" }.each do |flag, category|
      request = submit(photos: 1)
      Ai::Llm::Fake.respond_with(vision(safety: { flag => true }))
      error = assert_raises(Stories::Rejected) { Stories::PhotoCast.call(request) }
      assert_equal category, error.category
      assert_empty request.series.characters
    end
  end

  test "photos without people or animals: the cast plays in the photo places" do
    request = submit(photos: 1, cast: "travel")
    Ai::Llm::Fake.respond_with(vision(subjects: []))

    Stories::PhotoCast.call(request)

    assert_equal %w[grandma leo sora], request.series.characters.order(:key).pluck(:key)
    assert_equal "travel", request.reload.vision["cast"]
    assert_empty Ai::Image::Fake.calls
  end

  test "a character's sheet is drawn again from the same photo" do
    request = submit
    Ai::Llm::Fake.respond_with(vision)
    Stories::PhotoCast.call(request)
    man = request.series.characters.find_by!(key: "p1")
    blob = man.sheet.blob

    Stories::PhotoCast.new(request).redraw(man)

    assert_not_equal blob, man.reload.sheet.blob
    assert_equal 3, Ai::Image::Fake.calls.size
  end

  test "the whole comic: characters, the author confirms, the story; the photos are deleted at the end" do
    Rails.configuration.x.stories.generator = "pipeline"
    request = submit
    Ai::Llm::Fake.respond_with(vision)

    GenerateStoryJob.perform_now(request)
    assert request.reload.confirming?
    assert request.photos.attached?, "kept for redraws until the story is made"
    html = ApplicationController.render(partial: "stories/status", locals: { story_request: request })
    assert_includes html, "story-confirm"
    assert_includes html, 'value="Alex"'

    man = request.series.characters.find_by!(key: "p1")
    request.confirm!(names: { man.id.to_s => "Timur", "0" => "Nobody" }, voices: { man.id.to_s => "female" })
    assert_equal [ "Timur", "English_SentimentalLady" ], man.reload.values_at(:name, :voice)
    assert request.queued?

    answer = { "episode" => {
      "title" => "Timur and Buddy", "synopsis" => "A day at the beach.", "target_words" => %w[beach wave snack laugh dog],
      "panels" => Array.new(6) do |i|
        { "image_prompt" => "Wide shot: Timur and Buddy at the beach bar, moment #{i + 1}.",
          "bubbles" => [ { "kind" => "speech", "character" => "p1", "text" => "Buddy, give me back my snack!", "translation" => "Бадди, верни мой перекус!" } ] }
      end } }
    markup = { "bubbles" => Array.new(6) { |i| { "id" => "p#{i + 1}b1", "tokens" => en_tokens("Buddy, give me back my snack!") } } }
    Ai::Llm::Fake.respond_with(answer, markup)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { GenerateStoryJob.perform_now(request) }

    assert request.reload.succeeded?, request.error
    assert request.episode.reload.published?
    assert_not request.reload.photos.attached?
    prompt = Ai::Llm::Fake.calls[1][:messages].map { |m| m[:content] }.join("\n")
    assert_includes prompt, "photo 2: the man laughs on a wakeboard"
    assert_includes prompt, "Our weekend at the beach"
    assert_includes prompt, "p1 = Timur (protagonist)"
  ensure
    Rails.configuration.x.stories.generator = "fake"
  end
end
