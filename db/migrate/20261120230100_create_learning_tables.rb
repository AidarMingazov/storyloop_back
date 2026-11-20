class CreateLearningTables < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.references :language_pair, foreign_key: true
      t.string :self_level
      t.datetime :onboarded_at
      t.jsonb :utm, null: false, default: {}
    end

    create_table :user_words do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lexeme, null: false, foreign_key: true
      t.references :source_token, foreign_key: { to_table: :tokens, on_delete: :nullify }

      # FSRS card state (fsrs_ruby, FSRS v6)
      t.datetime :due, null: false
      t.float :stability, null: false, default: 0
      t.float :difficulty, null: false, default: 0
      t.integer :elapsed_days, null: false, default: 0
      t.integer :scheduled_days, null: false, default: 0
      t.integer :learning_steps, null: false, default: 0
      t.integer :reps, null: false, default: 0
      t.integer :lapses, null: false, default: 0
      t.integer :state, null: false, default: 0 # 0 new, 1 learning, 2 review, 3 relearning
      t.datetime :last_review
      t.timestamps
    end
    add_index :user_words, %i[user_id lexeme_id], unique: true
    add_index :user_words, %i[user_id due]

    create_table :reading_progresses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :episode, null: false, foreign_key: true
      t.integer :last_panel_position, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end
    add_index :reading_progresses, %i[user_id episode_id], unique: true

    create_table :generation_logs do |t|
      t.references :episode, foreign_key: true
      t.string :step, null: false # script | images | layout | tokens | audio
      t.string :provider
      t.string :model
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :images, null: false, default: 0
      t.integer :characters, null: false, default: 0 # TTS input
      t.decimal :cost_usd, precision: 10, scale: 5, null: false, default: 0
      t.integer :duration_ms
      t.string :status, null: false, default: "running"
      t.text :error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :generation_logs, %i[episode_id step]

    create_table :waitlist_entries do |t|
      t.string :email, null: false
      t.references :language_pair, foreign_key: true
      t.references :user, foreign_key: true
      t.string :plan
      t.string :source
      t.jsonb :utm, null: false, default: {}
      t.timestamps
    end
    add_index :waitlist_entries, :email, unique: true
  end
end
