# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_21_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bubbles", force: :cascade do |t|
    t.bigint "panel_id", null: false
    t.bigint "character_id"
    t.integer "position", null: false
    t.string "kind", null: false
    t.text "text", null: false
    t.text "translation"
    t.jsonb "box"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_bubbles_on_character_id"
    t.index ["panel_id", "position"], name: "index_bubbles_on_panel_id_and_position", unique: true
    t.index ["panel_id"], name: "index_bubbles_on_panel_id"
  end

  create_table "characters", force: :cascade do |t|
    t.bigint "series_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "appearance_prompt"
    t.boolean "protagonist", default: false, null: false
    t.string "voice"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["series_id", "key"], name: "index_characters_on_series_id_and_key", unique: true
    t.index ["series_id"], name: "index_characters_on_series_id"
  end

  create_table "episodes", force: :cascade do |t|
    t.bigint "series_id", null: false
    t.integer "number", null: false
    t.string "title", null: false
    t.string "format", null: false
    t.string "cefr_level", null: false
    t.string "status", default: "draft", null: false
    t.boolean "free", default: false, null: false
    t.integer "estimated_minutes"
    t.text "synopsis"
    t.string "target_words", default: [], null: false, array: true
    t.jsonb "script_json"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["series_id", "number"], name: "index_episodes_on_series_id_and_number", unique: true
    t.index ["series_id"], name: "index_episodes_on_series_id"
    t.index ["status"], name: "index_episodes_on_status"
  end

  create_table "generation_logs", force: :cascade do |t|
    t.bigint "episode_id"
    t.string "step", null: false
    t.string "provider"
    t.string "model"
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "images", default: 0, null: false
    t.integer "characters", default: 0, null: false
    t.decimal "cost_usd", precision: 10, scale: 5, default: "0.0", null: false
    t.integer "duration_ms"
    t.string "status", default: "running", null: false
    t.text "error"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id", "step"], name: "index_generation_logs_on_episode_id_and_step"
    t.index ["episode_id"], name: "index_generation_logs_on_episode_id"
  end

  create_table "language_pairs", force: :cascade do |t|
    t.string "code", null: false
    t.string "target_lang", null: false
    t.string "native_lang", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_language_pairs_on_code", unique: true
  end

  create_table "lexemes", force: :cascade do |t|
    t.string "language", null: false
    t.string "lemma", null: false
    t.string "pos", null: false
    t.string "cefr_level"
    t.string "romanization"
    t.jsonb "translations", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language", "lemma", "pos"], name: "index_lexemes_on_language_and_lemma_and_pos", unique: true
  end

  create_table "panels", force: :cascade do |t|
    t.bigint "episode_id", null: false
    t.integer "position", null: false
    t.text "image_prompt"
    t.jsonb "layout", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id", "position"], name: "index_panels_on_episode_id_and_position", unique: true
    t.index ["episode_id"], name: "index_panels_on_episode_id"
  end

  create_table "reading_progresses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "episode_id", null: false
    t.integer "last_panel_position", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id"], name: "index_reading_progresses_on_episode_id"
    t.index ["user_id", "episode_id"], name: "index_reading_progresses_on_user_id_and_episode_id", unique: true
    t.index ["user_id"], name: "index_reading_progresses_on_user_id"
  end

  create_table "series", force: :cascade do |t|
    t.bigint "language_pair_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description"
    t.string "genre"
    t.string "cefr_level", null: false
    t.text "style_prompt"
    t.string "status", default: "draft", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language_pair_id", "slug"], name: "index_series_on_language_pair_id_and_slug", unique: true
    t.index ["language_pair_id"], name: "index_series_on_language_pair_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tokens", force: :cascade do |t|
    t.bigint "bubble_id", null: false
    t.bigint "lexeme_id", null: false
    t.integer "start_offset", null: false
    t.integer "end_offset", null: false
    t.string "surface", null: false
    t.string "context_translation", null: false
    t.text "context_note"
    t.string "romanization"
    t.jsonb "breakdown"
    t.string "politeness"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bubble_id", "start_offset"], name: "index_tokens_on_bubble_id_and_start_offset", unique: true
    t.index ["bubble_id"], name: "index_tokens_on_bubble_id"
    t.index ["lexeme_id"], name: "index_tokens_on_lexeme_id"
  end

  create_table "user_words", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lexeme_id", null: false
    t.bigint "source_token_id"
    t.datetime "due", null: false
    t.float "stability", default: 0.0, null: false
    t.float "difficulty", default: 0.0, null: false
    t.integer "elapsed_days", default: 0, null: false
    t.integer "scheduled_days", default: 0, null: false
    t.integer "learning_steps", default: 0, null: false
    t.integer "reps", default: 0, null: false
    t.integer "lapses", default: 0, null: false
    t.integer "state", default: 0, null: false
    t.datetime "last_review"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lexeme_id"], name: "index_user_words_on_lexeme_id"
    t.index ["source_token_id"], name: "index_user_words_on_source_token_id"
    t.index ["user_id", "due"], name: "index_user_words_on_user_id_and_due"
    t.index ["user_id", "lexeme_id"], name: "index_user_words_on_user_id_and_lexeme_id", unique: true
    t.index ["user_id"], name: "index_user_words_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address"
    t.string "password_digest"
    t.boolean "guest", default: false, null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "language_pair_id"
    t.string "self_level"
    t.datetime "onboarded_at"
    t.jsonb "utm", default: {}, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["language_pair_id"], name: "index_users_on_language_pair_id"
  end

  create_table "waitlist_entries", force: :cascade do |t|
    t.string "email", null: false
    t.bigint "language_pair_id"
    t.bigint "user_id"
    t.string "plan"
    t.string "source"
    t.jsonb "utm", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_waitlist_entries_on_email", unique: true
    t.index ["language_pair_id"], name: "index_waitlist_entries_on_language_pair_id"
    t.index ["user_id"], name: "index_waitlist_entries_on_user_id"
  end

  create_table "word_reviews", force: :cascade do |t|
    t.bigint "user_word_id", null: false
    t.bigint "user_id", null: false
    t.integer "rating", null: false
    t.integer "state", null: false
    t.integer "elapsed_days", default: 0, null: false
    t.integer "scheduled_days", default: 0, null: false
    t.datetime "due_before", null: false
    t.datetime "due_after", null: false
    t.datetime "reviewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "reviewed_at"], name: "index_word_reviews_on_user_id_and_reviewed_at"
    t.index ["user_id"], name: "index_word_reviews_on_user_id"
    t.index ["user_word_id"], name: "index_word_reviews_on_user_word_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bubbles", "characters"
  add_foreign_key "bubbles", "panels"
  add_foreign_key "characters", "series"
  add_foreign_key "episodes", "series"
  add_foreign_key "generation_logs", "episodes"
  add_foreign_key "panels", "episodes"
  add_foreign_key "reading_progresses", "episodes"
  add_foreign_key "reading_progresses", "users"
  add_foreign_key "series", "language_pairs"
  add_foreign_key "sessions", "users"
  add_foreign_key "tokens", "bubbles"
  add_foreign_key "tokens", "lexemes"
  add_foreign_key "user_words", "lexemes"
  add_foreign_key "user_words", "tokens", column: "source_token_id", on_delete: :nullify
  add_foreign_key "user_words", "users"
  add_foreign_key "users", "language_pairs"
  add_foreign_key "waitlist_entries", "language_pairs"
  add_foreign_key "waitlist_entries", "users"
  add_foreign_key "word_reviews", "user_words", on_delete: :cascade
  add_foreign_key "word_reviews", "users"
end
