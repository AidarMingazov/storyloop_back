require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "guests need no email or password" do
    assert User.new(guest: true).valid?
  end

  test "registered users need an email and a password of 8+ characters" do
    user = User.new

    assert_not user.valid?
    assert user.errors.of_kind?(:email_address, :blank)
    assert user.errors.of_kind?(:password, :blank)

    user.assign_attributes(email_address: "mia@example.com", password: "short")
    assert user.errors.of_kind?(:password, :too_short) unless user.valid?

    user.password = "long enough"
    assert user.valid?
  end

  test "authenticates by email and password" do
    assert_equal users(:one), User.authenticate_by(email_address: "one@example.com", password: "password")
    assert_nil User.authenticate_by(email_address: "one@example.com", password: "wrong")
  end
end
