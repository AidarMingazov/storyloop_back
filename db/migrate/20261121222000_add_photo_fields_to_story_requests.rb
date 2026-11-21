class AddPhotoFieldsToStoryRequests < ActiveRecord::Migration[8.1]
  # Comic from own photos (7.11): what the vision model saw, when the author confirmed the characters, sheet redraws.
  def change
    add_column :story_requests, :vision, :jsonb, default: {}, null: false
    add_column :story_requests, :confirmed_at, :datetime
    add_column :story_requests, :redraws, :integer, default: 0, null: false
  end
end
