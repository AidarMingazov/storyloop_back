require "application_system_test_case"

# The wave 7 demo on the fake generator: create a story → share the link → a guest reads it without an
# account → the author makes it public → it is in the feed → a report takes it out.
class UserStoriesTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper # jobs wait in the test adapter; the test runs them

  def sign_in(user)
    visit new_session_path
    fill_in "email_address", with: user.email_address # the browser asks for English before sign-in
    fill_in "password", with: "password"
    find("form input[type=submit]").click
    assert_no_current_path new_session_path
  end

  test "create → share → guest reads → public → feed → report hides" do
    author = users(:one)
    author.update!(language_pair: language_pairs(:en_ru), onboarded_at: Time.current)
    sign_in author

    visit new_story_path
    find("label", text: "Своя идея").click
    fill_in "story_prompt_idea", with: "A cat detective looks for a lost cake"
    assert_no_selector "#story_prompt_text" # other modes' inputs are hidden
    select "A2", from: "Уровень"
    fill_in "Подпись автора", with: "Mia"
    check "story_rules_accepted"
    click_on "Создать"
    assert_text "Создаём историю…"
    perform_enqueued_jobs # the fake generator; in the app the status updates over Turbo Streams
    refresh
    assert_text "История готова!"
    link = find("#share-link").value
    assert_match %r{/s/\w{12}\?ref=#{author.public_id}&utm_campaign=story&utm_medium=link&utm_source=share\z}, link

    click_on "Читать"
    assert_selector ".reader .tok", minimum: 1
    assert_text "Это ваша история · По ссылке"
    click_on "Поделиться историей"
    assert_selector "[data-share-toast]"

    # a friend opens the link: no account, reads right away
    Capybara.reset_session!
    visit URI(link).request_uri
    assert_selector ".reader .tok", minimum: 1
    assert_text "Автор Mia"
    assert User.last.guest?

    # not in the feed yet: it is "by link"
    visit community_path
    assert_selector "#community-empty"

    Capybara.reset_session!
    sign_in author
    visit stories_path
    click_on "A cat detective looks for a lost cake"
    choose "Для всех", allow_label_click: true
    click_on "Сохранить"
    assert_text "Видимость: Для всех"

    Capybara.reset_session!
    visit community_path
    click_on "A cat detective looks for a lost cake"
    assert_selector ".reader .tok", minimum: 1
    find("#report summary").click
    choose "Спам или реклама", allow_label_click: true
    click_on "Отправить жалобу"
    assert_text "Спасибо! История скрыта для вас"
    assert_no_text "A cat detective looks for a lost cake"

    Capybara.reset_session!
    visit community_path
    assert_selector "#community-empty" # out of the feed for everyone until a moderator decides

    assert_equal %w[story_created story_ready share_opened story_published story_reported],
                 tracked_events & %w[story_created story_ready share_opened story_published story_reported]
  end

  test "story by voice: the recording becomes text in the idea field" do
    users(:one).update!(language_pair: language_pairs(:en_ru), onboarded_at: Time.current) # the form in Russian
    sign_in users(:one)
    visit new_story_path
    find("label", text: "Своя идея").click
    fill_in "story_prompt_idea", with: "Cats."

    # Docker serves the app over plain http on an IP, where browsers hide the microphone API: a test tone stands in.
    execute_script <<~JS
      const tone = () => { const ctx = new AudioContext(); const osc = ctx.createOscillator(); const out = ctx.createMediaStreamDestination();
                           osc.connect(out); osc.start(); return out.stream }
      Object.defineProperty(navigator, "mediaDevices", { value: { getUserMedia: async () => tone() }, configurable: true })
      document.getElementById("voice-input").hidden = false
    JS
    find("#voice-input").click
    assert_selector "#voice-input[aria-pressed=true]"
    sleep 1.5 # record a moment of the tone
    find("#voice-input").click

    assert_field "story_prompt_idea", with: "Cats. #{Ai::Stt::Fake::DEFAULT_TEXT}"
    assert_selector "#voice-input[aria-pressed=false]:not([disabled])"
    log = GenerationLog.where(step: "stt").sole
    assert_operator log.metadata["bytes"], :>, 30_000, "about 1.5 s of 16 kHz WAV"
  end

  test "comic from photos: upload, confirm the characters, read; private by default" do
    author = users(:one)
    author.update!(language_pair: language_pairs(:en_ru), onboarded_at: Time.current)
    sign_in author

    visit new_story_path
    find("label", text: "Из фото").click
    assert_checked_field "story_visibility_private", visible: :all # real people: only the author by default
    attach_file "story_photos", [ file_fixture("photo.jpg").to_s, file_fixture("photo.jpg").to_s ]
    fill_in "story_prompt_photos", with: "Our trip to the sea"
    check "story_photos_consent"
    check "story_rules_accepted"
    click_on "Создать"
    assert_text "Создаём историю…"

    perform_enqueued_jobs # the fake generator draws placeholder characters, one per photo
    refresh
    within "#story-confirm" do
      assert_selector "img", count: 2
      first("input[type=text]").fill_in(with: "Timur")
      click_on "Создать комикс"
    end
    assert_text "Создаём историю…"
    assert_selector "[data-step=vision][data-state=done]"

    perform_enqueued_jobs
    refresh
    click_on "Читать"
    assert_selector ".reader .tok", minimum: 1
    request = StoryRequest.last
    assert_equal "Timur", request.series.characters.find_by!(key: "p1").name
    assert_not request.photos.attached?, "originals are deleted once the story is made"
  end

  test "every other way to create: a theme, own text, surprise me; a private story stays closed to guests" do
    author = users(:one)
    author.update!(language_pair: language_pairs(:en_ru), onboarded_at: Time.current, display_name: "Mia")
    sign_in author

    { "Тема" => -> { find("[data-modes=theme] label", text: "Детектив").click },
      "Свой текст" => -> { fill_in "story_prompt_text", with: "Masha lost her keys and found them in the fridge." },
      "Удиви меня" => -> { } }.each do |mode, fill|
      visit new_story_path
      find("label", text: mode).click
      fill.call
      choose "story_visibility_private", allow_label_click: true
      check "story_rules_accepted"
      click_on "Создать"
      assert_text "Создаём историю…"
      perform_enqueued_jobs
      refresh
      assert_selector "#read-story"
    end

    assert_equal %w[theme text surprise], StoryRequest.order(:id).pluck(:mode)
    assert_equal [ "detective", "cafe" ], StoryRequest.order(:id).first(2).map(&:cast_key)
    token = StoryRequest.last.episode.share_token

    Capybara.reset_session!
    visit shared_episode_path(token)
    assert_selector "#story-unavailable"
  end
end
