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

  test "spike M.0: a webtoon reader gets their motion variant and the setting; every event carries the variant" do
    with_motion_lite("ab") do
      get episode_path(@episode)
      variant = MotionLite.variant(User.last.analytics_id)
      assert_includes %w[motion static], variant
      assert_select ".reader[data-reader-motion-default-value=?]", variant
      assert_select "#pref_motion"
      assert_equal variant, tracked("episode_started").sole[:properties][:motion_variant]
      context = JSON.parse(css_select("meta[name='analytics-context']").first["content"])
      assert_equal variant, context["motion_variant"], "browser events get it from analytics-context"
    end
  end

  test "spike M.0 off, or not a webtoon: no motion, no setting, no variant" do
    get episode_path(@episode)
    assert_select ".reader[data-reader-motion-default-value='']"
    assert_select "#pref_motion", false
    assert_not tracked("episode_started").sole[:properties].key?(:motion_variant)

    with_motion_lite("on") do
      chat = Episodes::Importer.call(file_fixture("episode_ko.json").read, status: "published")
      get episode_path(chat)
      assert_select ".reader[data-reader-motion-default-value='']"
      assert_select "#pref_motion", false
    end
  end

  def with_motion_lite(mode)
    previous = Rails.configuration.x.reader.motion_lite
    Rails.configuration.x.reader.motion_lite = mode
    yield
  ensure
    Rails.configuration.x.reader.motion_lite = previous
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

  test "paid episodes show the paywall with prices for the pair" do
    @episode.update!(free: false)
    get episode_path(@episode)
    assert_response :success
    assert_select "h1", "Читайте все эпизоды"
    assert_select "[data-controller=reader]", count: 0
    assert_select "label", /Год.*5 990 ₽/m
    assert_equal 1, tracked("paywall_viewed").size
  end

  test "episode_started is tracked once per reader and episode" do
    get episode_path(@episode)
    get episode_path(@episode)

    events = tracked("episode_started")
    assert_equal 1, events.size
    assert_equal({ pair: "en-ru", format: "webtoon", episode_number: 1, episode_level: "A2", guest: true },
                 events.first[:properties].slice(:pair, :format, :episode_number, :episode_level, :guest))
    assert_equal User.last.analytics_id, events.first[:distinct_id]
  end
end
