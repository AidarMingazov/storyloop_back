require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "lists published series without signing in" do
    Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
    get root_path
    assert_response :success
    assert_select "h3", "Test Café"
  end
end
