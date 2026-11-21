class AddCastKeyToStoryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :story_requests, :cast_key, :string # db/templates/ai/casts/<key>.yml (7.4)
  end
end
