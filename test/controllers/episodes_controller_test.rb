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

  test "the settings offer the story's other languages once it is translated" do
    get episode_path(@episode)
    assert_select "#reader-settings #story-editions", false, "one language: nothing to switch to"

    korean = Episodes::Importer.call(file_fixture("episode_ko.json").read, status: "published")
    korean.update!(origin_episode: @episode)

    get episode_path(@episode)
    assert_select "#story-editions a.chip", 2
    assert_select "#story-editions a.chip.is-on[aria-current=true]", "Английский"
    assert_select "#story-editions a.chip[href='#{episode_path(korean)}']", "Корейский"

    get episode_path(korean) # and back from the translation, in its own interface language
    assert_select "#story-editions a.chip[href='#{episode_path(@episode)}']", "English"

    korean.review! # not published: readers do not see it
    get episode_path(@episode)
    assert_select "#story-editions", false
  end

  test "the header carries the language pill and the settings are a sheet of switches and choices" do
    get episode_path(@episode)
    assert_select ".reader-header .reader-pill[aria-controls=reader-settings]", /EN · A2/
    assert_select "#reader-settings.sheet[inert]" do
      assert_select "button.switch[role=switch]#pref_translations"
      assert_select "button.switch#pref_highlight"
      assert_select "button.switch#pref_romanization", false, "romanization is for Korean"
      assert_select "button.chip[data-pref=size]", 3
      assert_select "button.chip[data-pref=theme]", 3
      assert_select "button.chip[data-pref=page_turn]", false, "page turns are for manga"
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
