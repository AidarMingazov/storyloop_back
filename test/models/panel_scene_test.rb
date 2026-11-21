require "test_helper"

class PanelSceneTest < ActiveSupport::TestCase
  SCENE = { "v" => 1, "setting" => "exterior", "place" => "street", "time" => "night", "weather" => "rain", "light" => "neon",
            "mood" => "tense", "shot" => "wide", "focus" => nil, "elements" => %w[city_lights] }.freeze

  test "values and fields come from the schema" do
    assert_equal %w[close medium wide], PanelScene.values(:shot)
    assert_includes PanelScene.values("elements"), "petals"
    assert_includes PanelScene.values("place"), "museum", "galleries were tagged \"other\" before"
    assert_equal %w[setting place time weather light mood shot focus elements], PanelScene.fields
    assert_raises(ArgumentError) { PanelScene.values("smell") }
  end

  test "errors name the field" do
    assert_empty PanelScene.errors(SCENE)
    assert_empty PanelScene.errors(SCENE.except("focus", "elements")), "focus and elements are optional"

    errors = PanelScene.errors(SCENE.merge("mood" => "grumpy", "elements" => %w[a b c d], "extra" => 1))
    assert errors.any? { |e| e.start_with?("mood: ") }
    assert errors.any? { |e| e.start_with?("elements") }
    assert errors.any? { |e| e.include?("extra") }
    assert PanelScene.errors(SCENE.except("v")).any?, "the version is required"
  end

  test "a panel keeps an empty scene or a valid one" do
    panel = Episodes::Importer.call(file_fixture("episode_en.json").read).panels.first
    assert_equal({}, panel.scene)

    assert panel.update(scene: SCENE)
    assert_not panel.update(scene: SCENE.merge("shot" => "extreme"))
    assert_match(/shot: /, panel.errors[:scene].first)
  end

  test "labels for the admin" do
    assert_equal %w[exterior street night rain neon tense wide city_lights], PanelScene.labels(SCENE)
    assert_includes PanelScene.labels(SCENE.merge("focus" => "mia")), "→ mia"
  end
end
