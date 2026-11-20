require "test_helper"
require "socket"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Mobile-first: system tests run at a phone viewport.
  PHONE = [ 390, 844 ].freeze

  if ENV["SELENIUM_REMOTE_URL"].present?
    # Docker: Chrome lives in the `chrome` service and calls back into this container.
    driven_by :selenium, using: :headless_chrome, screen_size: PHONE,
              options: { browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] }

    Capybara.server_host = "0.0.0.0"
    Capybara.app_host = "http://#{IPSocket.getaddress(Socket.gethostname)}"
    Capybara.always_include_port = true # each parallel worker gets its own port
  else
    driven_by :selenium, using: :headless_chrome, screen_size: PHONE
  end
end
