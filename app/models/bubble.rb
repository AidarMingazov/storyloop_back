class Bubble < ApplicationRecord
  KINDS = %w[speech thought narration chat_message].freeze
  BOX_KEYS = %w[x y w h].freeze

  belongs_to :panel
  belongs_to :character, optional: true
  has_one :episode, through: :panel
  has_many :tokens, -> { order(:start_offset) }, dependent: :destroy
  has_one_attached :audio

  enum :kind, KINDS.index_by(&:itself), validate: true

  validates :text, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: :panel_id }
  validate :box_is_percent_rect

  private
    def box_is_percent_rect
      return if box.nil?

      valid = box.is_a?(Hash) && box.keys.sort == BOX_KEYS.sort &&
              box.values.all? { |v| v.is_a?(Numeric) && v.between?(0, 100) }
      errors.add(:box, "must be {x, y, w, h} in percent (0–100)") unless valid
    end
end
