require "test_helper"
require "socket"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Mobile-first: system tests run at a phone viewport.
  PHONE = [ 390, 844 ].freeze

  # Docker Desktop runs Postgres, Puma and Chrome on ~3 GB: give pages a bit more time.
  Capybara.default_max_wait_time = 5

  if ENV["SELENIUM_REMOTE_URL"].present?
    # Docker: Chrome lives in the `chrome` service and calls back into this container.
    driven_by :selenium, using: :headless_chrome, screen_size: PHONE,
              options: { browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] } do |chrome|
      chrome.add_argument("--force-prefers-reduced-motion") # no sliding sheet mid-click
    end

    Capybara.server_host = "0.0.0.0"
    Capybara.app_host = "http://#{IPSocket.getaddress(Socket.gethostname)}"
    Capybara.always_include_port = true # each parallel worker gets its own port
  else
    driven_by(:selenium, using: :headless_chrome, screen_size: PHONE) { |chrome| chrome.add_argument("--force-prefers-reduced-motion") }
  end

  # A real click at a point of the element, given as fractions of its box (Selenium offsets from the centre).
  # The element must be fully on screen: WebDriver measures from the centre of its visible part.
  def tap_at(element, x:, y:)
    rect = element.rect
    page.driver.browser.action
        .move_to(element.native, ((x - 0.5) * rect.width).round, ((y - 0.5) * rect.height).round).click.perform
  end

  # A real click on a bubble outside its words: the top padding, at the horizontal centre.
  def tap_padding(element)
    page.driver.browser.action.move_to(element.native, 0, 3 - (element.rect.height / 2).floor).click.perform
  end

  # Runs the block at a desktop viewport (the suite's default is a phone). DevTools emulation, not a window
  # resize: resizing the window of the remote headless Chrome hangs.
  def at_desktop(width = 1280, height = 900)
    visit "/up" # a session and a page to emulate on
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: false)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
