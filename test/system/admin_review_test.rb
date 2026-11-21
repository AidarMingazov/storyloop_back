require "application_system_test_case"

class AdminReviewTest < ApplicationSystemTestCase
  test "admin signs in, opens an episode for review and publishes it" do
    episode = Episodes::Importer.call(file_fixture("episode_en.json").read)

    visit new_session_path
    fill_in "email_address", with: users(:admin).email_address
    fill_in "password", with: "password"
    find("input[type=submit]").click
    assert_current_path root_path # wait for the session cookie before navigating

    visit admin_series_index_path
    click_on "Test Café"
    click_on "Spilled"

    assert_text "Guess who I ran into today!"
    assert_selector "figure img" # placeholder image rendered
    click_on "Опубликовать"

    assert_text "Эпизод опубликован"
    assert episode.reload.published?
  end
end
