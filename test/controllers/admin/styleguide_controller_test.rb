require "test_helper"

class Admin::StyleguideControllerTest < ActionDispatch::IntegrationTest
  test "admins see every component in both themes" do
    sign_in_as users(:admin)
    get admin_styleguide_path

    assert_response :success
    assert_select "h1", "Дизайн-система"
    assert_select "[data-theme-sample=paper]:not(.theme-night)"
    assert_select "[data-theme-sample=midnight].theme-night"
    %w[colors type scripts buttons icons chips controls words overlays states].each do |section|
      assert_select "[data-theme-sample] [data-section=#{section}]", 2, "section #{section} in both themes"
    end
    assert_select "[data-theme-sample=paper] [data-icon]", DesignHelper::ICONS.size
  end

  test "the page loads the Japanese and Chinese faces for its script samples" do
    sign_in_as users(:admin)
    get admin_styleguide_path

    assert_select "link[rel=stylesheet][href*='Noto+Sans+JP'][href*='Noto+Sans+SC']"
  end

  test "the sprite is on admin, product and reader pages" do
    sign_in_as users(:admin)
    get admin_styleguide_path
    assert_select "svg symbol#i-play"

    get root_path
    assert_select "svg symbol#i-play"
  end

  test "non-admins get 404" do
    sign_in_as users(:one)
    get admin_styleguide_path

    assert_response :not_found
  end
end
