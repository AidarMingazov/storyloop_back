class AddGenerationFieldsToSeriesAndCharacters < ActiveRecord::Migration[8.1]
  def change
    # Series template for the AI pipeline (wave 6). tone — story mood for the script prompt; art_style — drawing style
    # only, for character sheets (style_prompt stays the full panel style with places and light); narrator_voice — TTS
    # voice of narration bubbles, distinct from every character's voice.
    add_column :series, :tone, :text
    add_column :series, :art_style, :text
    add_column :series, :narrator_voice, :string
    # One Korean speech level per character for the whole series: casual (반말) / polite (해요체) / formal (합쇼체).
    add_column :characters, :speech_level, :string
  end
end
