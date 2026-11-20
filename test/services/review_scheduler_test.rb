require "test_helper"

class ReviewSchedulerTest < ActiveSupport::TestCase
  setup do
    @episode = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    @word = users(:guest).user_words.create!(lexeme: @episode.tokens.first.lexeme)
    @now = Time.zone.parse("2026-11-21 10:00")
  end

  test "a new card offers short learning steps and a long easy interval" do
    intervals = ReviewScheduler.new(@word, now: @now).intervals

    assert_equal 1.minute, intervals["again"]
    assert_equal 10.minutes, intervals["good"]
    assert_operator intervals["easy"], :>=, 1.day
    assert_equal %w[again hard good easy], intervals.keys
  end

  test "answering moves the card and logs the review" do
    ReviewScheduler.new(@word, now: @now).answer!("good")
    @word.reload

    assert_equal FsrsRuby::State::LEARNING, @word.state
    assert_equal 1, @word.reps
    assert_equal @now + 10.minutes, @word.due
    assert_equal @now, @word.last_review

    review = @word.word_reviews.sole
    assert_equal 3, review.rating
    assert_equal FsrsRuby::State::NEW, review.state
  end

  test "good twice graduates the card to review with a day-scale interval" do
    ReviewScheduler.new(@word, now: @now).answer!("good")
    ReviewScheduler.new(@word.reload, now: @now + 10.minutes).answer!("good")
    @word.reload

    assert_equal FsrsRuby::State::REVIEW, @word.state
    assert_operator @word.due, :>=, @now + 1.day
  end

  test "forgetting a learned card counts a lapse" do
    ReviewScheduler.new(@word, now: @now).answer!("easy")
    later = @word.reload.due
    ReviewScheduler.new(@word, now: later).answer!("again")

    assert_equal 1, @word.reload.lapses
    assert_equal FsrsRuby::State::RELEARNING, @word.state
  end

  test "rejects unknown ratings" do
    assert_raises(ArgumentError) { ReviewScheduler.new(@word, now: @now).answer!("meh") }
  end

  test "review queue holds due cards and learning cards back within minutes" do
    soon = users(:guest).user_words.create!(lexeme: @episode.tokens.second.lexeme, due: 5.minutes.from_now)
    later = users(:guest).user_words.create!(lexeme: @episode.tokens.third.lexeme, due: 2.days.from_now)

    assert_equal [ @word, soon ], users(:guest).user_words.review_queue.to_a
    assert_not_includes users(:guest).user_words.due_today(1.hour.from_now), later
  end
end
