require "application_system_test_case"

class FunnelSystemTest < ApplicationSystemTestCase
  setup do
    @free = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    paid = JSON.parse(file_fixture("reader_webtoon.json").read)
    paid["episode"].merge!("number" => 2, "title" => "Paid", "free" => false)
    Episodes::Importer.call(paid, status: "published")
  end

  test "landing → level → first episode → save a word → signup prompt → paywall → waitlist" do
    visit landing_path(pair: "en-ru", utm_source: "ads")
    assert_text "Учите английский по комиксам"
    click_on "Читать первый эпизод бесплатно", match: :first

    assert_text "Какой у вас уровень?"
    choose "A2 · Знаю основы", allow_label_click: true
    click_on "Читать первый эпизод"

    assert_current_path episode_path(@free)
    # browser-only analytics go to posthog-js; stub it to see what the reader sends
    execute_script "window.posthog = { capture: (name) => (window.sent ||= []).push(name) }"
    find(".tok", text: "ran into").click
    within(".word-sheet.is-open") { click_on "Сохранить слово" }
    assert_selector ".tok.is-saved", text: "ran into"
    assert_includes evaluate_script("window.sent"), "token_tapped"

    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    within ".reader-summary" do
      assert_text "Сохраните прогресс и слова"
      click_on "Следующий эпизод — по подписке"
    end

    assert_text "Читайте все эпизоды"
    choose "Месяц", allow_label_click: true
    click_on "Оплатить"

    assert_text "Мы запускаем оплату на этой неделе"
    fill_in "Email", with: "mia@example.com"
    click_on "Оставить email"
    assert_text "Спасибо!"

    assert_equal %w[landing_viewed onboarding_completed episode_started word_saved episode_completed
                    paywall_viewed checkout_clicked waitlist_email_submitted], tracked_events
    assert_equal "ads", User.last.utm["utm_source"]
    assert_equal "monthly", WaitlistEntry.sole.plan
  end
end
