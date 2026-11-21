require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "guests need no email or password" do
    assert User.new(guest: true).valid?
  end

  test "registered users need an email; a password is optional (magic link) but 8+ characters" do
    user = User.new

    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)

    user.email_address = "mia@example.com"
    assert user.valid?, "magic-link users have no password"

    user.password = "short"
    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)

    user.password = "long enough"
    assert user.valid?
  end

  test "a guest registers on the same record" do
    guest = users(:guest)
    assert guest.register(email_address: "new@example.com", password: "long enough")
    assert_not guest.reload.guest?
    assert guest.authenticate("long enough")

    other = User.create!(guest: true)
    assert_not other.register(email_address: "new@example.com", password: "long enough")
    assert other.errors.of_kind?(:email_address, :taken)
  end

  test "absorbing a guest moves words and progress and keeps the furthest reading position" do
    episode = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    lexemes = episode.tokens.first(2).map(&:lexeme)
    account = users(:one)
    guest = users(:guest)

    account.user_words.create!(lexeme: lexemes.first)
    guest_word = guest.user_words.create!(lexeme: lexemes.first)
    guest_word.word_reviews.create!(user: guest, rating: 3, state: 0, due_before: Time.current, due_after: Time.current, reviewed_at: Time.current)
    guest.user_words.create!(lexeme: lexemes.second)
    account.reading_progresses.create!(episode: episode, last_panel_position: 1)
    guest.reading_progresses.create!(episode: episode, last_panel_position: 2, completed_at: Time.current)

    account.absorb_guest!(guest)

    assert_not User.exists?(guest.id)
    assert_equal lexemes.map(&:id).sort, account.user_words.pluck(:lexeme_id).sort
    progress = account.reading_progresses.sole
    assert_equal 2, progress.last_panel_position
    assert progress.completed?
  end

  test "magic login tokens work once" do
    user = users(:one)
    token = user.generate_token_for(:magic_login)
    assert_equal user, User.find_by_token_for(:magic_login, token)

    user.update!(magic_login_at: Time.current)
    assert_nil User.find_by_token_for(:magic_login, token)
  end

  test "authenticates by email and password" do
    assert_equal users(:one), User.authenticate_by(email_address: "one@example.com", password: "password")
    assert_nil User.authenticate_by(email_address: "one@example.com", password: "wrong")
  end
end
