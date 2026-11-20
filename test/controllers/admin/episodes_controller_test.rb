require "test_helper"

class Admin::EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @en = Episodes::Importer.call(file_fixture("episode_en.json").read)
    @ko = Episodes::Importer.call(file_fixture("episode_ko.json").read)
  end

  test "review screen shows panels, bubbles and tokens" do
    get admin_episode_path(@en)
    assert_response :success
    assert_select "h1", /Spilled/
    assert_select "span[title='run into — случайно встретила']", "ran into"
    assert_select "td", "phrasal_verb"
  end

  test "review screen for a Korean chat episode shows romanization and breakdown" do
    get admin_episode_path(@ko)
    assert_response :success
    assert_select "td", /pigonhaeyo/
    assert_select "td", /피곤하 \(stem\) \+ -아\/어요 \(ending\)/
  end

  test "publish and unpublish" do
    post publish_admin_episode_path(@en)
    assert @en.reload.published?
    assert @en.published_at

    post unpublish_admin_episode_path(@en)
    assert @en.reload.review?
  end

  test "update episode metadata and target words" do
    patch admin_episode_path(@en), params: { episode: { title: "Spilled coffee", free: "0", target_words_text: "run into, by the way" } }
    assert_redirected_to admin_episode_path(@en)
    assert_equal "Spilled coffee", @en.reload.title
    assert_not @en.free?
    assert_equal [ "run into", "by the way" ], @en.target_words
  end

  test "editing bubble text warns about tokens that no longer match" do
    bubble = @en.bubbles.first
    patch admin_bubble_path(bubble), params: { bubble: { kind: "speech", text: "Guess who I met today!", translation: "", box_json: bubble.box.to_json } }
    follow_redirect!
    assert_select "#notice", /ran into/
  end

  test "rejects a bubble box that is not JSON" do
    bubble = @en.bubbles.first
    patch admin_bubble_path(bubble), params: { bubble: { kind: "speech", text: bubble.text, box_json: "{oops" } }
    assert_response :unprocessable_entity
  end

  test "token form creates the lexeme and finds the offsets" do
    bubble = @en.bubbles.first
    bubble.tokens.find_by!(surface: "today").destroy

    assert_difference -> { bubble.tokens.count } do
      post admin_bubble_tokens_path(bubble), params: { token_form: {
        surface: "today", context_translation: "сегодня", lemma: "today", pos: "adverb", lemma_translation: "сегодня"
      } }
    end
    token = bubble.tokens.find_by!(surface: "today")
    assert_equal [ 21, 26 ], [ token.start_offset, token.end_offset ]
  end

  test "token form rejects a surface that is not in the text" do
    bubble = @en.bubbles.first
    post admin_bubble_tokens_path(bubble), params: { token_form: {
      surface: "tomorrow", context_translation: "завтра", lemma: "tomorrow", pos: "adverb"
    } }
    assert_response :unprocessable_entity
  end
end
