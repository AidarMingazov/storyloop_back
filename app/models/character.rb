class Character < ApplicationRecord
  # Same values as Token::POLITENESS: 반말 / 해요체 / 합쇼체. The script prompt keeps a character on one level.
  SPEECH_LEVELS = Token::POLITENESS
  SPEECH_LEVEL_NAMES = { "casual" => "반말", "polite" => "해요체", "formal" => "합쇼체" }.freeze

  belongs_to :series
  has_many :bubbles, dependent: :nullify
  has_one_attached :avatar
  has_many_attached :reference_images
  # Reference sheet (4 views on a plain background) passed to the image model for every panel with this character.
  has_one_attached :sheet

  normalizes :speech_level, with: ->(value) { value.presence }

  validates :name, presence: true
  validates :key, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, uniqueness: { scope: :series_id }
  validates :speech_level, inclusion: { in: SPEECH_LEVELS }, allow_nil: true
end
