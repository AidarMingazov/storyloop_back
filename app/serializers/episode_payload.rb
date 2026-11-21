# Everything the reader needs in one JSON: panels, bubbles, tokens and a deduplicated lexeme map.
# The web reader embeds it in the page; API v1 (wave 5) returns the same shape, so every client
# renders from one format. Token offsets are codepoints (JS: Array.from(text)).
class EpisodePayload
  include Rails.application.routes.url_helpers

  def initialize(episode, user: nil)
    @episode = episode
    @user = user
  end

  def as_json(*)
    {
      id: episode.id,
      number: episode.number,
      title: episode.title,
      format: episode.format,
      cefr_level: episode.cefr_level,
      free: episode.free,
      estimated_minutes: episode.estimated_minutes,
      target_words: episode.target_words,
      language_pair: { code: pair.code, target_lang: pair.target_lang, native_lang: pair.native_lang },
      series: { id: series.id, slug: series.slug, title: series.title },
      characters: series.characters.map { |character| character_json(character) },
      panels: panels.map { |panel| panel_json(panel) },
      lexemes: lexemes.to_h { |lexeme| [ lexeme.id, lexeme_json(lexeme) ] },
      next_episode: next_episode_json,
      user: user_json
    }
  end

  def to_json(*) = as_json.to_json

  private
    attr_reader :episode, :user

    def series = episode.series
    def pair = series.language_pair

    def panels
      @panels ||= episode.panels.includes(image_attachment: :blob, bubbles: [ :tokens, { audio_attachment: :blob } ])
    end

    def lexeme_ids
      @lexeme_ids ||= panels.flat_map { |panel| panel.bubbles.flat_map { |bubble| bubble.tokens.map(&:lexeme_id) } }.uniq
    end

    def lexemes
      @lexemes ||= Lexeme.where(id: lexeme_ids).with_attached_audio.to_a
    end

    def character_json(character)
      { id: character.id, key: character.key, name: character.name, protagonist: character.protagonist,
        avatar_url: character.avatar.attached? ? rails_blob_path(character.avatar, only_path: true) : nil }
    end

    def panel_json(panel)
      { id: panel.id, position: panel.position, aspect_ratio: panel.aspect_ratio,
        image_url: panel.image.attached? ? rails_representation_path(panel.image.variant(:phone), only_path: true) : nil,
        bubbles: panel.bubbles.map { |bubble| bubble_json(bubble) } }
    end

    def bubble_json(bubble)
      { id: bubble.id, position: bubble.position, kind: bubble.kind, character_id: bubble.character_id,
        text: bubble.text, translation: bubble.translation, box: bubble.box,
        audio_url: bubble.audio.attached? ? rails_blob_path(bubble.audio, only_path: true) : nil,
        tokens: bubble.tokens.map { |token| token_json(token) } }
    end

    def token_json(token)
      { id: token.id, lexeme_id: token.lexeme_id, start: token.start_offset, end: token.end_offset,
        surface: token.surface, translation: token.context_translation, note: token.context_note,
        romanization: token.romanization, breakdown: token.breakdown, politeness: token.politeness }
    end

    def lexeme_json(lexeme)
      { id: lexeme.id, lemma: lexeme.lemma, pos: lexeme.pos, cefr_level: lexeme.cefr_level,
        romanization: lexeme.romanization, translation: lexeme.translation_for(pair.native_lang),
        audio_url: lexeme.audio.attached? ? rails_blob_path(lexeme.audio, only_path: true) : nil }
    end

    def next_episode_json
      following = episode.next_episode
      return unless following

      { id: following.id, number: following.number, title: following.title,
        locked: !(user&.can_read?(following) || following.free?) }
    end

    def user_json
      return unless user

      progress = user.reading_progresses.find_by(episode: episode)
      { guest: user.guest?,
        saved_lexeme_ids: user.user_words.where(lexeme_id: lexeme_ids).pluck(:lexeme_id),
        last_panel_position: progress&.last_panel_position || 0,
        completed: progress&.completed? || false }
    end
end
