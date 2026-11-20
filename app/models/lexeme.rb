class Lexeme < ApplicationRecord
  POS = %w[noun verb adjective adverb pronoun preposition conjunction interjection determiner numeral
           particle phrasal_verb idiom phrase].freeze

  has_many :tokens, dependent: :restrict_with_error
  has_many :user_words, dependent: :destroy
  has_one_attached :audio

  validates :language, :lemma, presence: true
  validates :pos, inclusion: { in: POS }
  validates :lemma, uniqueness: { scope: %i[language pos] }
  validates :cefr_level, inclusion: { in: Cefr::LEVELS }, allow_nil: true

  def translation_for(native_lang)
    translations[native_lang.to_s]
  end
end
