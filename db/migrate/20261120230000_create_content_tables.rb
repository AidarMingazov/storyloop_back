class CreateContentTables < ActiveRecord::Migration[8.1]
  def change
    create_table :language_pairs do |t|
      t.string :code, null: false            # en-ru
      t.string :target_lang, null: false     # language of the stories
      t.string :native_lang, null: false     # language of hints and UI
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :language_pairs, :code, unique: true

    create_table :series do |t|
      t.references :language_pair, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description
      t.string :genre
      t.string :cefr_level, null: false
      t.text :style_prompt
      t.string :status, null: false, default: "draft"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :series, %i[language_pair_id slug], unique: true

    create_table :characters do |t|
      t.references :series, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :appearance_prompt
      t.boolean :protagonist, null: false, default: false
      t.string :voice
      t.timestamps
    end
    add_index :characters, %i[series_id key], unique: true

    create_table :episodes do |t|
      t.references :series, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :title, null: false
      t.string :format, null: false
      t.string :cefr_level, null: false
      t.string :status, null: false, default: "draft"
      t.boolean :free, null: false, default: false
      t.integer :estimated_minutes
      t.text :synopsis
      t.string :target_words, array: true, null: false, default: []
      t.jsonb :script_json
      t.datetime :published_at
      t.timestamps
    end
    add_index :episodes, %i[series_id number], unique: true
    add_index :episodes, :status

    create_table :panels do |t|
      t.references :episode, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :image_prompt
      t.jsonb :layout, null: false, default: {}
      t.timestamps
    end
    add_index :panels, %i[episode_id position], unique: true

    create_table :bubbles do |t|
      t.references :panel, null: false, foreign_key: true
      t.references :character, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.text :text, null: false
      t.text :translation
      t.jsonb :box # {x, y, w, h} in percent of the panel image
      t.timestamps
    end
    add_index :bubbles, %i[panel_id position], unique: true

    create_table :lexemes do |t|
      t.string :language, null: false
      t.string :lemma, null: false
      t.string :pos, null: false
      t.string :cefr_level
      t.string :romanization
      t.jsonb :translations, null: false, default: {} # {"ru" => "...", "en" => "..."}
      t.timestamps
    end
    add_index :lexemes, %i[language lemma pos], unique: true

    create_table :tokens do |t|
      t.references :bubble, null: false, foreign_key: true
      t.references :lexeme, null: false, foreign_key: true
      t.integer :start_offset, null: false # codepoints, inclusive
      t.integer :end_offset, null: false   # codepoints, exclusive
      t.string :surface, null: false
      t.string :context_translation, null: false
      t.text :context_note
      t.string :romanization
      t.jsonb :breakdown # Korean: [{part, role, meaning}]
      t.string :politeness # Korean: casual | polite | formal
      t.timestamps
    end
    add_index :tokens, %i[bubble_id start_offset], unique: true
  end
end
