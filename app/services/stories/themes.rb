module Stories
  # Genre cards on "Create a story" (mode theme). Keys match series templates of the AI pipeline
  # where they exist (db/templates/ai/series/office-romance.yml); titles live in stories.*.yml.
  module Themes
    ICONS = {
      "office-romance" => "💼", "school" => "🎒", "idol" => "🎤", "detective" => "🔍",
      "fantasy" => "🐉", "travel" => "✈️", "cafe" => "☕", "folk-tale" => "🪓"
    }.freeze

    module_function

    def keys = ICONS.keys
    def icon(key) = ICONS[key]
    def title(key) = key && I18n.t("stories.themes.#{key}", default: key.to_s.humanize)
  end
end
