class CreateTranslationRequests < ActiveRecord::Migration[8.1]
  # "I want this story in my language" (7.8): demand for translations, one vote per reader, episode and pair.
  def change
    create_table :translation_requests do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :episode, null: false, foreign_key: { on_delete: :cascade }
      t.references :language_pair, null: false, foreign_key: true
      t.timestamps
      t.index %i[user_id episode_id language_pair_id], unique: true, name: "index_translation_requests_uniqueness"
    end
  end
end
