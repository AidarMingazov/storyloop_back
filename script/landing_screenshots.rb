# Takes the three reader screenshots each landing shows (app/assets/images/landing/<pair>-<n>.webp)
# from the running dev app, at iPhone size, through the Chrome container.
#
#   docker compose --profile test up -d chrome
#   docker compose run --rm -e SELENIUM_REMOTE_URL=http://chrome:4444 web bin/rails runner script/landing_screenshots.rb
#   docker compose --profile test stop chrome
#
# Needs the dev server (`docker compose up`) and seeds. Re-run after reader UI changes.
require "selenium-webdriver"
require "vips"

APP = ENV.fetch("APP_URL", "http://web:3000")
OUT = Rails.root.join("app/assets/images/landing")
IPHONE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) " \
            "Version/18.0 Mobile/15E148 Safari/604.1"

def driver
  options = Selenium::WebDriver::Chrome::Options.new(args: %w[--headless=new --hide-scrollbars --lang=en])
  options.add_emulation(device_metrics: { width: 390, height: 844, pixelRatio: 2, touch: true }, user_agent: IPHONE_UA)
  Selenium::WebDriver.for(:remote, url: ENV.fetch("SELENIUM_REMOTE_URL", "http://chrome:4444"), options: options)
end

def settle(browser, seconds = 0.6)
  Selenium::WebDriver::Wait.new(timeout: 15).until do
    browser.execute_script(<<~JS)
      const visible = (img) => { const r = img.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight }
      return document.fonts.status === "loaded" && [...document.images].filter(visible).every((img) => img.complete)
    JS
  end
  sleep seconds
end

def shoot(browser, name)
  png = OUT.join("#{name}.png")
  browser.save_screenshot(png.to_s)
  Vips::Image.new_from_file(png.to_s).webpsave(OUT.join("#{name}.webp").to_s, Q: 82)
  png.delete
  puts "saved #{name}.webp"
end

# Taps the first token of one of the episode's target words that has a note, near the top.
TAP_TARGET_WORD = <<~JS
  const payload = JSON.parse(document.querySelector("[data-reader-target=payload]").textContent)
  const targets = payload.target_words.map((w) => w.toLowerCase())
  const tokens = payload.panels.flatMap((p) => p.bubbles.flatMap((b) => b.tokens))
  const pick = tokens.find((t) => t.note && targets.includes(payload.lexemes[t.lexeme_id].lemma.toLowerCase())) || tokens.find((t) => t.note)
  for (let i = 0; i < 6; i++) document.querySelector(".chat-next-bar button")?.click()
  const el = document.querySelector(`[data-token-id="${pick.id}"]`)
  for (let i = 0; i < 12 && el.closest("[hidden]"); i++) document.querySelector(".chat-next-bar button")?.click()
  el.scrollIntoView({ block: "center" })
  el.click()
  return pick.surface
JS

def episode(pair_code, format, number: nil)
  scope = Episode.published.joins(series: :language_pair).where(language_pairs: { code: pair_code }, format: format)
  scope = scope.where(number: number) if number
  scope.order(:number).first!
end

def capture_pair(pair_code)
  browser = driver
  webtoon = episode(pair_code, "webtoon")
  word_episode = pair_code == "ko-en" ? episode(pair_code, "chat") : webtoon

  browser.navigate.to "#{APP}/start?pair=#{pair_code}" # sets up the device as a guest of this pair
  browser.navigate.to "#{APP}/episodes/#{webtoon.id}"
  settle(browser)
  shoot(browser, "#{pair_code}-1")

  browser.execute_script("localStorage.setItem('storyloop:romanization', '#{pair_code == 'ko-en' ? 1 : 0}')")
  browser.navigate.to "#{APP}/episodes/#{word_episode.id}"
  settle(browser)
  word = browser.execute_script(TAP_TARGET_WORD)
  settle(browser, 0.8)
  shoot(browser, "#{pair_code}-2")
  puts "  tapped #{word}"

  browser.find_element(css: "[data-sheet-action=save]").click
  sleep 0.8
  browser.navigate.to "#{APP}/review"
  settle(browser)
  browser.find_element(css: "[data-action='flashcard#show']").click
  settle(browser, 0.4)
  shoot(browser, "#{pair_code}-3")
ensure
  browser&.quit
end

OUT.mkpath
%w[en-ru ko-en].each { |code| capture_pair(code) }
