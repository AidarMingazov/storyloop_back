require "test_helper"

class FunnelTest < ActionDispatch::IntegrationTest
  setup do
    @en1 = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    paid = JSON.parse(file_fixture("reader_webtoon.json").read)
    paid["episode"].merge!("number" => 2, "title" => "Paid", "free" => false)
    @en2 = Episodes::Importer.call(paid, status: "published")
  end

  test "landing in the native language keeps UTM through onboarding" do
    get landing_path(pair: "en-ru", utm_source: "tiktok", utm_campaign: "launch")
    assert_response :success
    assert_select "html[lang=ru]"
    assert_select "h1", "Учите английский по комиксам"
    assert_select "img[src*='landing/en-ru-1']"
    landing = tracked("landing_viewed").sole
    assert_equal({ utm_source: "tiktok", utm_campaign: "launch" }, landing[:properties].slice(:utm_source, :utm_campaign))

    get start_path(pair: "en-ru")
    assert_select "input[type=radio][value=A2]"

    post start_path, params: { pair: "en-ru", level: "A2" }
    assert_redirected_to episode_path(@en1)

    reader = User.last
    assert reader.guest?
    assert_equal [ "en-ru", "A2" ], [ reader.language_pair.code, reader.self_level ]
    assert reader.onboarded?
    assert_equal({ "utm_source" => "tiktok", "utm_campaign" => "launch" }, reader.utm)
    assert_equal landing[:distinct_id], reader.analytics_id, "the anonymous visitor becomes the guest"
    assert_equal reader.analytics_id, tracked("onboarding_completed").sole[:distinct_id]
  end

  test "Korean landing is in English; unknown pairs are 404" do
    get landing_path(pair: "ko-en")
    assert_select "html[lang=en]"
    assert_select "h1", "Learn Korean through comics"

    get "/en-ja"
    assert_response :not_found
  end

  test "onboarding without a pair asks for one, in the browser's language" do
    get start_path, headers: { "Accept-Language" => "en-US,en;q=0.9" }
    assert_select "h1", "What are you learning?"
    assert_select "a[href$='pair=en-ru'][lang=ru]", /Английский/
  end

  test "paywall fake door: checkout click, then email on the waitlist" do
    get episode_path(@en2)
    assert_select "h1", "Читайте все эпизоды"

    post checkout_path, params: { plan: "monthly", episode_id: @en2.id }
    assert_redirected_to new_waitlist_entry_path(plan: "monthly", episode_id: @en2.id)
    assert_equal({ plan: "monthly", payments_mode: "fake_door", episode_number: 2 },
                 tracked("checkout_clicked").sole[:properties].slice(:plan, :payments_mode, :episode_number))

    follow_redirect!
    assert_select "h1", "Мы запускаем оплату на этой неделе"

    assert_difference -> { WaitlistEntry.count } do
      post waitlist_entries_path, params: { waitlist_entry: { email: " Mia@Example.com ", plan: "monthly" } }
      post waitlist_entries_path, params: { waitlist_entry: { email: "mia@example.com", plan: "yearly" } }
    end
    entry = WaitlistEntry.sole
    assert_equal [ "mia@example.com", "yearly", "en-ru" ], [ entry.email, entry.plan, entry.language_pair.code ]
    assert_equal 2, tracked("waitlist_email_submitted").size
  end

  test "a guest registers on the same record and keeps the analytics id" do
    get episode_path(@en1)
    guest = User.last

    post registration_path, params: { email_address: "mia@example.com", password: "long enough" }
    assert_redirected_to root_path

    assert_equal guest.id, User.registered.find_by!(email_address: "mia@example.com").id
    assert_equal guest.analytics_id, tracked("signup").sole[:distinct_id]
  end

  test "registering with a taken email sends you to sign in" do
    get episode_path(@en1)
    post registration_path, params: { email_address: users(:one).email_address, password: "long enough" }
    assert_redirected_to new_session_path(email_address: users(:one).email_address)
  end

  test "signing in after reading as a guest keeps the guest's words" do
    get episode_path(@en1)
    token = @en1.tokens.first
    post user_words_path, params: { lexeme_id: token.lexeme_id, token_id: token.id }, as: :json
    guest = User.last

    post session_path, params: { email_address: "one@example.com", password: "password" }

    assert_not User.exists?(guest.id)
    assert_equal [ token.lexeme_id ], users(:one).user_words.pluck(:lexeme_id)
  end

  test "magic link signs an existing user in once" do
    assert_enqueued_emails 1 do
      post magic_link_path, params: { email_address: "one@example.com" }
    end
    assert_redirected_to new_magic_link_path(sent: "one@example.com")

    token = users(:one).generate_token_for(:magic_login)
    get magic_link_path(token: token)
    assert_redirected_to root_path
    assert cookies[:session_id].present?

    get magic_link_path(token: token)
    assert_redirected_to new_magic_link_path
  end

  test "magic link turns the current guest into a registered user" do
    get episode_path(@en1)
    guest = User.last

    perform_enqueued_jobs do
      post magic_link_path, params: { email_address: "new@example.com" }
    end
    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://\S+}]
    get link.sub("http://example.com", "")

    guest.reload
    assert_not guest.guest?
    assert_equal "new@example.com", guest.email_address
    assert_equal "magic_link", tracked("signup").sole[:properties][:method]
  end
end
