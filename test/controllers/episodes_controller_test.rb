require "test_helper"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @episode = Episodes::Importer.call(file_fixture("episode_en.json").read, status: "published")
  end

  test "a first-time visitor reads without signing up and becomes a guest" do
    assert_difference -> { User.where(guest: true).count } do
      get episode_path(@episode)
    end
    assert_response :success
    assert cookies[:session_id].present?
    assert_select "script[type='application/json'][data-reader-target=payload]"
    assert_select "html[lang=ru]", true, "en-ru hints are Russian"

    assert_no_difference -> { User.count } do
      get episode_path(@episode)
    end
  end

  test "Korean pair renders the English interface" do
    ko = Episodes::Importer.call(file_fixture("episode_ko.json").read, status: "published")
    get episode_path(ko)
    assert_select "html[lang=en]"
    assert_select "#pref_romanization"
  end

  test "unpublished episodes are hidden from readers but open for admins" do
    @episode.review!
    get episode_path(@episode)
    assert_response :not_found

    sign_in_as users(:admin)
    get episode_path(@episode)
    assert_response :success
  end

  test "paid episodes show the locked screen" do
    @episode.update!(free: false)
    get episode_path(@episode)
    assert_response :success
    assert_select "h1", "Этот эпизод — по подписке"
    assert_select "[data-controller=reader]", count: 0
  end
end
