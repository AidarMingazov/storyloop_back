require "test_helper"

class UserWordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    @token = @episode.tokens.find_by!(surface: "ran into")
    get episode_path(@episode) # becomes a guest
    @user = User.last
  end

  test "saves a word with the token it came from, idempotently" do
    assert_difference -> { @user.user_words.count } do
      post user_words_path, params: { lexeme_id: @token.lexeme_id, token_id: @token.id }, as: :json
      post user_words_path, params: { lexeme_id: @token.lexeme_id, token_id: @token.id }, as: :json
    end
    assert_response :created
    word = @user.user_words.last
    assert_equal @token, word.source_token
    assert_equal 0, word.state # FSRS "new"
    assert word.due <= Time.current
  end

  test "unsaves a word" do
    @user.user_words.create!(lexeme: @token.lexeme)
    delete user_word_path(@token.lexeme_id), as: :json
    assert_response :success
    assert_equal 0, @user.user_words.count
  end
end
