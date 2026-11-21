require "test_helper"

class Api::V1::ApiTest < ActionDispatch::IntegrationTest
  setup do
    @free = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    paid = JSON.parse(file_fixture("reader_webtoon.json").read)
    paid["episode"].merge!("number" => 2, "title" => "Paid", "free" => false)
    @paid = Episodes::Importer.call(paid, status: "published")
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def guest_token
    post api_v1_guests_path, params: { language_pair: "en-ru", level: "A2" }, as: :json
    response.parsed_body["token"]
  end

  test "a guest gets a token and reads a free episode with absolute media URLs and their state" do
    token = guest_token
    assert_response :created

    get api_v1_episode_path(@free), headers: auth(token)
    assert_response :success
    json = response.parsed_body
    assert_equal "webtoon", json["format"]
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/representations/}, json["panels"].first["image_url"]
    assert_match(/ 800w, .* 1200w\z/, json["panels"].first["image_srcset"])
    assert_equal({ "guest" => true, "saved_lexeme_ids" => [], "last_panel_position" => 0, "completed" => false }, json["user"])
    assert_equal true, json["next_episode"]["locked"]
    assert_equal [ "episode_started" ], tracked_events
  end

  test "anonymous clients read free episodes without a user section" do
    get api_v1_episode_path(@free)
    assert_response :success
    assert_nil response.parsed_body["user"]
  end

  test "paid episodes answer 402 with the paywall plans" do
    get api_v1_episode_path(@paid), headers: auth(guest_token)
    assert_response :payment_required
    assert_equal "subscription_required", response.parsed_body["error"]
    assert_equal "5 990 ₽", response.parsed_body.dig("paywall", "plans", "yearly", "price")
  end

  test "unpublished episodes are 404" do
    @free.review!
    get api_v1_episode_path(@free)
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
  end

  test "save, list and remove words; progress moves forward" do
    token = guest_token
    tok = @free.tokens.find_by!(surface: "ran into")

    post api_v1_user_words_path, params: { lexeme_id: tok.lexeme_id, token_id: tok.id }, headers: auth(token), as: :json
    assert_response :created
    get api_v1_user_words_path, headers: auth(token)
    assert_equal [ "run into" ], response.parsed_body.map { |w| w["lemma"] }

    patch api_v1_episode_progress_path(@free), params: { last_panel_position: 2, completed: true }, headers: auth(token), as: :json
    assert_equal({ "last_panel_position" => 2, "completed" => true }, response.parsed_body)
    assert_equal %w[word_saved episode_completed], tracked_events

    delete api_v1_user_word_path(tok.lexeme_id), headers: auth(token)
    assert_response :no_content
  end

  test "word calls need a token" do
    post api_v1_user_words_path, params: { lexeme_id: 1 }, as: :json
    assert_response :unauthorized
  end

  test "signing in with a guest token moves the guest's words into the account" do
    token = guest_token
    tok = @free.tokens.first
    post api_v1_user_words_path, params: { lexeme_id: tok.lexeme_id }, headers: auth(token), as: :json

    post api_v1_sessions_path, params: { email_address: "one@example.com", password: "password" }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ tok.lexeme_id ], users(:one).user_words.pluck(:lexeme_id)

    post api_v1_sessions_path, params: { email_address: "one@example.com", password: "wrong" }, as: :json
    assert_response :unauthorized
  end
end
