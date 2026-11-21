# Design system helpers (wave Р1): sprite icons and the web fonts a page needs.
# Tokens and component classes live in app/assets/tailwind/application.css; preview at /admin/styleguide.
module DesignHelper
  # Every <symbol id="i-…"> in shared/_icons. reader/icons.js draws the same sprite on the client.
  ICONS = %w[
    back chevron-right chevron-down arrow-right arrow-down
    play pause prev next sound translate
    bookmark bookmark-fill check close plus lock
    pen mic stop redo book eye settings cc share search sparkle sun moon
  ].freeze

  # Latin and Korean faces load on every page; Japanese and Chinese only where the page has such text.
  FONT_FAMILIES = {
    base: [
      "Inter:wght@400;500;600;700",
      "Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;1,8..60,400",
      "Noto+Sans+KR:wght@400;500;700",
      "Noto+Serif+KR:wght@500;600"
    ],
    "ja" => [ "Noto+Sans+JP:wght@400;500;700" ],
    "zh" => [ "Noto+Sans+SC:wght@400;500;700" ]
  }.freeze

  # <svg class="icon"><use href="#i-play"></use></svg>. Decorative unless `label:` is given.
  def icon(name, label: nil, **options)
    name = name.to_s.dasherize
    raise ArgumentError, "Unknown icon: #{name}" unless ICONS.include?(name)

    a11y = label ? { role: "img", aria: { label: } } : { aria: { hidden: true } }
    attributes = a11y.merge(options).merge(class: class_names("icon", options[:class]), viewBox: "0 0 24 24")
    tag.svg(tag.use(href: "#i-#{name}"), **attributes)
  end

  # Called from a view whose text is in these languages (target_lang of a pair, a styleguide sample).
  def use_fonts_for(*langs)
    (@font_langs ||= Set.new).merge(langs.flatten.compact.map { |lang| lang.to_s.split("-").first })
    nil
  end

  def google_fonts_url
    families = FONT_FAMILIES[:base] + (@font_langs || []).flat_map { |lang| FONT_FAMILIES.fetch(lang, []) }
    "https://fonts.googleapis.com/css2?#{families.map { |family| "family=#{family}" }.join("&")}&display=swap"
  end
end
