require "test_helper"

class Admin::AccessTest < ActionDispatch::IntegrationTest
  test "anonymous visitors are sent to sign in" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "signed-in non-admins get 404" do
    sign_in_as users(:one)
    get admin_root_path
    assert_response :not_found
  end

  test "admins see the series list" do
    sign_in_as users(:admin)
    get admin_root_path
    assert_response :success
    assert_select "h1", "Серии"
  end
end
