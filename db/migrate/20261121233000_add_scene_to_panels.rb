# Tags of what a panel shows (config/schemas/scene.json) for the motion player — wave M, docs/motion-research.md.
class AddSceneToPanels < ActiveRecord::Migration[8.1]
  def change
    add_column :panels, :scene, :jsonb, default: {}, null: false
  end
end
