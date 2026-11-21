# Wave 7: stories made by users, share links, moderation, the community feed.
class AddUserStories < ActiveRecord::Migration[8.1]
  def change
    # A user story is a series (source: user) with episode #1. Ownership, visibility and moderation
    # live on the series; catalog series keep the defaults (public, approved) and behave as before.
    change_table :series, bulk: true do |t|
      t.references :author, foreign_key: { to_table: :users }
      t.string :source, null: false, default: "catalog"
      t.string :visibility, null: false, default: "public"
      t.string :moderation_state, null: false, default: "approved"
      t.index %i[source visibility moderation_state]
    end

    # Links point at an episode (catalog episodes are shareable too); counters sort the feed.
    change_table :episodes, bulk: true do |t|
      t.string :share_token
      t.references :origin_episode, foreign_key: { to_table: :episodes, on_delete: :nullify } # translated from (7.8)
      t.integer :reads_count, null: false, default: 0
      t.integer :saves_count, null: false, default: 0
      t.integer :shares_count, null: false, default: 0
    end

    change_table :users, bulk: true do |t|
      t.string :public_id # author page and share `ref`; never the email or the analytics id
      t.string :display_name
      t.datetime :banned_at
      t.references :referrer, foreign_key: { to_table: :users, on_delete: :nullify } # came via someone's share link
    end

    reversible do |dir|
      dir.up do
        backfill :episodes, :share_token, 12
        backfill :users, :public_id, 10
      end
    end

    change_column_null :episodes, :share_token, false
    add_index :episodes, :share_token, unique: true
    change_column_null :users, :public_id, false
    add_index :users, :public_id, unique: true

    # The brief for one generation: what the pipeline (wave 6, 7.4) reads, and what limits count.
    create_table :story_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :series, null: false, foreign_key: { on_delete: :cascade }
      t.references :episode, null: false, foreign_key: { on_delete: :cascade }
      t.references :language_pair, null: false, foreign_key: true
      t.string :mode, null: false # theme | idea | text | surprise (later: photos, voice)
      t.string :theme
      t.text :prompt
      t.string :cefr_level, null: false
      t.string :format, null: false
      t.string :status, null: false, default: "queued"
      t.string :step
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
      t.index %i[user_id created_at]
    end

    create_table :reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :episode, null: false, foreign_key: { on_delete: :cascade }
      t.string :reason, null: false
      t.text :comment
      t.string :status, null: false, default: "open"
      t.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resolved_at
      t.timestamps
      t.index %i[reporter_id episode_id], unique: true
      t.index %i[status created_at]
    end

    # "Hide author": the user no longer sees this author's stories in the feed.
    create_table :author_blocks do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :author, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
      t.index %i[user_id author_id], unique: true
    end
  end

  private
    def backfill(table, column, length)
      select_values("SELECT id FROM #{table} WHERE #{column} IS NULL").each do |id|
        execute "UPDATE #{table} SET #{column} = #{quote(SecureRandom.base58(length))} WHERE id = #{id.to_i}"
      end
    end
end
