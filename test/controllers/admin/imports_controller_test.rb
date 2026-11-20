require "test_helper"

class Admin::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "imports pasted JSON" do
    assert_difference -> { Episode.count } do
      post admin_imports_path, params: { json: file_fixture("episode_en.json").read, publish: "1" }
    end
    episode = Episode.last
    assert_redirected_to admin_episode_path(episode)
    assert episode.published?
  end

  test "shows schema errors" do
    post admin_imports_path, params: { json: { language_pair: "en-ru" }.to_json }
    assert_response :unprocessable_entity
    assert_select "li", /series/
  end
end
