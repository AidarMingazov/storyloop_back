# Admin form for one token together with its lexeme. Finds or creates the lexeme by
# (language, lemma, pos); offsets are located automatically when left blank.
class TokenForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  FIELDS = %i[surface start_offset end_offset context_translation context_note romanization politeness breakdown_json
              lemma pos lemma_translation cefr_level lemma_romanization].freeze

  attribute :surface, :string
  attribute :start_offset, :integer
  attribute :end_offset, :integer
  attribute :context_translation, :string
  attribute :context_note, :string
  attribute :romanization, :string
  attribute :politeness, :string
  attribute :breakdown_json, :string
  attribute :lemma, :string
  attribute :pos, :string
  attribute :lemma_translation, :string
  attribute :cefr_level, :string
  attribute :lemma_romanization, :string

  attr_reader :token

  validates :surface, :lemma, :context_translation, presence: true
  validates :pos, inclusion: { in: Lexeme::POS }

  def initialize(token:, **attrs)
    @token = token
    # A submitted form carries every field, so blanks there are real edits (e.g. clearing a note).
    super(**(attrs.empty? ? defaults : attrs.symbolize_keys))
  end

  def self.model_name = ActiveModel::Name.new(self, nil, "TokenForm")

  def persisted? = token.persisted?
  def bubble = token.bubble
  def pair = bubble.episode.series.language_pair

  def save
    return false unless valid?

    breakdown = parse_breakdown
    start, finish = offsets
    return false if errors.any?

    Token.transaction do
      lexeme = Lexeme.find_or_initialize_by(language: pair.target_lang, lemma: lemma, pos: pos)
      lexeme.translations = lexeme.translations.merge(pair.native_lang => lemma_translation.presence || context_translation)
      lexeme.cefr_level = cefr_level.presence || lexeme.cefr_level
      lexeme.romanization = lemma_romanization.presence || lexeme.romanization
      lexeme.save!

      token.update!(lexeme: lexeme, surface: surface, start_offset: start, end_offset: finish,
                    context_translation: context_translation, context_note: context_note.presence,
                    romanization: romanization.presence, politeness: politeness.presence, breakdown: breakdown)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.each { |message| errors.add(:base, message) }
    false
  end

  private
    def defaults
      return {} unless token.persisted?

      lexeme = token.lexeme
      { surface: token.surface, start_offset: token.start_offset, end_offset: token.end_offset,
        context_translation: token.context_translation, context_note: token.context_note,
        romanization: token.romanization, politeness: token.politeness,
        breakdown_json: token.breakdown && JSON.pretty_generate(token.breakdown),
        lemma: lexeme.lemma, pos: lexeme.pos, lemma_translation: lexeme.translation_for(pair.native_lang),
        cefr_level: lexeme.cefr_level, lemma_romanization: lexeme.romanization }
    end

    def offsets
      return [ start_offset, end_offset || start_offset + surface.length ] if start_offset

      Token.locate(bubble.text, surface).tap do |located|
        errors.add(:surface, "не найдено в тексте пузыря") unless located
      end
    end

    def parse_breakdown
      JSON.parse(breakdown_json) if breakdown_json.present?
    rescue JSON::ParserError
      errors.add(:breakdown_json, "не JSON")
      nil
    end
end
