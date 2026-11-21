# Tags of what a panel shows (panels.scene, config/schemas/scene.json): written by Ai::Steps::Scene, copied with the
# panels when an episode is translated, read by the motion player (wave M, docs/motion-research.md).
#
#   PanelScene.values("mood")   # => ["calm", "happy", …] — the prompt lists them from the schema
#   PanelScene.errors(scene)    # => ["mood: …"], empty when the tags are valid
module PanelScene
  VERSION = 1
  SCHEMA_PATH = Rails.root.join("config/schemas/scene.json")

  module_function

  def schema = @schema ||= JSONSchemer.schema(SCHEMA_PATH)

  def definition = @definition ||= JSON.parse(SCHEMA_PATH.read)

  # Every tag field, in schema order (without the version).
  def fields = definition["properties"].keys - [ "v" ]

  def values(field)
    property = definition["properties"][field.to_s] || raise(ArgumentError, "unknown scene field #{field.inspect}")
    property["enum"] || property.dig("items", "enum")
  end

  def errors(scene)
    schema.validate(scene).map do |error|
      field = error["data_pointer"].delete_prefix("/").presence || "scene"
      "#{field}: #{error['error']}"
    end
  end

  # Short labels for the admin: ["interior", "cafe", "evening", "rain", …, "→ mia", "steam"].
  def labels(scene)
    fields.flat_map do |field|
      value = scene[field]
      field == "focus" ? (value && "→ #{value}") : value
    end.compact_blank
  end
end
