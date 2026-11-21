require "application_system_test_case"

# Spike M.0: light motion in the webtoon reader (reader/motion_lite.js, MotionLite).
module MotionLiteSystemHelper
  def self.included(base)
    base.setup do
      @mode = Rails.configuration.x.reader.motion_lite
      Rails.configuration.x.reader.motion_lite = "on"
      @episode = Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
    end
    base.teardown { Rails.configuration.x.reader.motion_lite = @mode }
  end

  def panel(position) = ".wt-panel[data-position='#{position}']"

  def animations(position) = evaluate_script("document.querySelector(\"#{panel(position)} img\").getAnimations().length")

  # Server-side events arrive from a request the page sends on its own.
  def eventually(timeout: Capybara.default_max_wait_time)
    deadline = Time.current + timeout
    sleep 0.05 until yield || Time.current > deadline
    assert yield
  end

  # Chrome in system tests asks for reduced motion (ApplicationSystemTestCase), and the Docker Chrome runs one
  # session, so a second driver is not an option: the page is told motion is fine over CDP instead (nil resets).
  # Remote Selenium has no execute_cdp, so Chrome's bridge commands are added to the remote bridge.
  def emulate_motion(allowed)
    bridge = page.driver.browser.send(:bridge)
    bridge.extend(Selenium::WebDriver::Chrome::Features) unless bridge.respond_to?(:send_command)
    features = allowed.nil? ? [] : [ { name: "prefers-reduced-motion", value: allowed ? "no-preference" : "reduce" } ]
    bridge.send_command(cmd: "Emulation.setEmulatedMedia", params: { features: })
  end
end

class MotionLiteSystemTest < ApplicationSystemTestCase
  include MotionLiteSystemHelper

  setup { emulate_motion(true) }
  teardown { emulate_motion(nil) }

  test "the picture zooms in and the bubbles appear as a panel comes into view; words stay tappable; the setting turns it off" do
    visit episode_path(@episode)
    execute_script "window.posthog = { capture: (name, props) => (window.sent ||= []).push([name, props]) }"

    assert_selector "#{panel(0)}[data-motion=done]"
    assert_no_selector "#{panel(0)} .wt-bubble.is-motion-hidden", visible: :all
    assert_equal 1, animations(0), "the zoom of the first panel"
    assert_selector "#{panel(2)}[data-motion=waiting]"
    assert_selector "#{panel(2)} .wt-bubble.is-motion-hidden", visible: :hidden

    find(".tok", text: "ran into").click
    assert_selector ".word-sheet.is-open", text: "случайно встретила"
    assert_equal true, evaluate_script("window.sent.find(([name]) => name === 'token_tapped')[1].motion")
    find("body").send_keys(:escape)

    find("[aria-label='Настройки']").click
    find("#pref_motion").set(false)
    assert_no_selector ".wt-bubble.is-motion-hidden", visible: :all
    assert_equal 0, animations(0), "the zoom is cancelled"

    execute_script "window.scrollTo(0, document.body.scrollHeight)"
    assert_selector ".reader-summary", text: "Эпизод прочитан"
    eventually { tracked("episode_completed").any? }
    properties = tracked("episode_completed").sole[:properties]
    assert_equal [ false, "motion" ], properties.values_at(:motion, :motion_variant)

    visit episode_path(@episode)
    assert_not find("#pref_motion", visible: :all).checked?, "the choice is remembered on the device"
    assert_no_selector ".wt-bubble.is-motion-hidden", visible: :all
  end

  test "panels the reader has already passed stay as they are" do
    visit episode_path(@episode)
    User.last.reading_progresses.find_by!(episode: @episode).update!(last_panel_position: 2)

    visit episode_path(@episode)
    assert_selector "#{panel(0)}[data-motion=done]", visible: :all
    assert_selector "#{panel(1)}[data-motion=done]", visible: :all
    assert_equal 0, animations(0)
  end
end

class MotionLiteReducedMotionTest < ApplicationSystemTestCase
  include MotionLiteSystemHelper

  test "with reduced motion asked by the system nothing moves and the setting says why" do
    visit episode_path(@episode)

    assert_no_selector ".wt-bubble.is-motion-hidden", visible: :all
    assert_equal 0, animations(0)
    find("[aria-label='Настройки']").click
    assert find("#pref_motion").disabled?
    assert_text "Выключена системной настройкой «Уменьшение движения»"
  end
end
