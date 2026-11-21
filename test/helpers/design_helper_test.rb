require "test_helper"

class DesignHelperTest < ActionView::TestCase
  test "an icon points at its sprite symbol and is hidden from screen readers by default" do
    html = Nokogiri::HTML5.fragment(icon(:play, class: "size-6"))
    svg = html.at_css("svg")

    assert_equal "icon size-6", svg["class"]
    assert_equal "0 0 24 24", svg["viewbox"] || svg["viewBox"]
    assert_equal "true", svg["aria-hidden"]
    assert_equal "#i-play", svg.at_css("use")["href"]
  end

  test "a labelled icon is announced as an image" do
    svg = Nokogiri::HTML5.fragment(icon(:lock, label: "Subscribers only")).at_css("svg")

    assert_equal "img", svg["role"]
    assert_equal "Subscribers only", svg["aria-label"]
    assert_nil svg["aria-hidden"]
  end

  test "underscored names map to the dashed symbol ids" do
    assert_includes icon(:bookmark_fill), "#i-bookmark-fill"
  end

  test "an unknown icon is a programming error" do
    assert_raises(ArgumentError) { icon(:rocket) }
  end

  test "every icon name has a symbol in the sprite, and the sprite has nothing extra" do
    sprite = File.read(Rails.root.join("app/views/shared/_icons.html.erb"))
    symbols = sprite.scan(/<symbol id="i-([a-z-]+)"/).flatten

    assert_equal DesignHelper::ICONS.sort, symbols.sort
  end

  test "Japanese and Chinese faces load only when a page asks for them" do
    assert_includes google_fonts_url, "family=Noto+Sans+KR"
    assert_not_includes google_fonts_url, "Noto+Sans+JP"

    use_fonts_for "ja", "zh-Hans", nil
    url = google_fonts_url

    assert_includes url, "family=Noto+Sans+JP"
    assert_includes url, "family=Noto+Sans+SC"
    assert url.end_with?("&display=swap")
  end
end
