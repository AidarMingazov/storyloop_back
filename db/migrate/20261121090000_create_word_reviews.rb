class CreateWordReviews < ActiveRecord::Migration[8.1]
  # One row per flashcard answer: retention metrics now, FSRS parameter optimization later.
  def change
    create_table :word_reviews do |t|
      t.references :user_word, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: true
      t.integer :rating, null: false        # 1 again, 2 hard, 3 good, 4 easy
      t.integer :state, null: false         # card state before the answer
      t.integer :elapsed_days, null: false, default: 0
      t.integer :scheduled_days, null: false, default: 0
      t.datetime :due_before, null: false
      t.datetime :due_after, null: false
      t.datetime :reviewed_at, null: false
      t.timestamps
    end
    add_index :word_reviews, %i[user_id reviewed_at]
  end
end
