class AddRejectionToStoryRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :story_requests, :rejection, :string # Stories::REJECTIONS category when moderation stopped the story (7.6)
  end
end
