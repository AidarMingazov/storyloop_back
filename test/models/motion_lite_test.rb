require "test_helper"

class MotionLiteTest < ActiveSupport::TestCase
  setup { @mode = Rails.configuration.x.reader.motion_lite }
  teardown { Rails.configuration.x.reader.motion_lite = @mode }

  def mode!(value) = Rails.configuration.x.reader.motion_lite = value

  test "tests run with the spike off" do
    assert_equal "off", MotionLite.mode
    assert_not MotionLite.enabled?
    assert_nil MotionLite.variant("0b6c4c5e-6c1a-4f6e-9f0e-2d1f6a0f9a11")
  end

  test "ab splits readers in half by id, the same id always the same way" do
    mode!("ab")
    ids = Array.new(2000) { |i| format("00000000-0000-4000-8000-%012d", i) }
    variants = ids.map { |id| MotionLite.variant(id) }

    assert_equal variants, ids.map { |id| MotionLite.variant(id) }
    assert_equal %w[motion static], variants.uniq.sort
    assert_in_delta 1000, variants.count("motion"), 100
    assert_nil MotionLite.variant(nil)
  end

  test "on gives everyone motion; an unknown mode is off" do
    mode!("on")
    assert_equal "motion", MotionLite.variant("anyone")
    mode!("sometimes")
    assert_equal "off", MotionLite.mode
    assert_nil MotionLite.variant("anyone")
  end
end
