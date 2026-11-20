require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    @token = @episode.tokens.find_by!(surface: "ran into")
  end

  test "visitors without words see the empty state" do
    get review_path
    assert_response :success
    assert_select "h2", "Пока нечего повторять"
  end

  test "shows the sentence with the word marked, then answers move to the done screen" do
    get episode_path(@episode) # guest; their pair (en-ru) sets the Russian interface
    post user_words_path, params: { lexeme_id: @token.lexeme_id, token_id: @token.id }, as: :json
    word = User.last.user_words.sole

    get review_path
    assert_response :success
    assert_select "mark", "ran into"
    assert_select "button", /Хорошо\s*10 мин/

    post answer_review_path, params: { user_word_id: word.id, rating: "easy" }
    assert_redirected_to review_path
    assert_operator word.reload.due, :>, 1.day.from_now

    follow_redirect!
    assert_select "h2", "На сегодня всё"
    assert_select "p", "Повторено сегодня: 1"
  end

  test "Korean learners get the English interface" do
    ko = Episodes::Importer.call(file_fixture("episode_ko.json").read, status: "published")
    get episode_path(ko)
    token = ko.tokens.find_by!(surface: "피곤해요")
    post user_words_path, params: { lexeme_id: token.lexeme_id, token_id: token.id }, as: :json

    get review_path
    assert_select "h1", "Review"
    assert_select "span.badge", /해요체 · polite/
  end

  test "cannot answer someone else's card" do
    other = users(:one).user_words.create!(lexeme: @token.lexeme)
    get episode_path(@episode)

    post answer_review_path, params: { user_word_id: other.id, rating: "good" }
    assert_response :not_found
  end

  test "rejects unknown ratings" do
    get episode_path(@episode)
    word = User.last.user_words.create!(lexeme: @token.lexeme)

    post answer_review_path, params: { user_word_id: word.id, rating: "meh" }
    assert_response :unprocessable_entity
  end
end
