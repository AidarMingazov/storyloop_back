class Token < ApplicationRecord
  POLITENESS = %w[casual polite formal].freeze

  belongs_to :bubble
  belongs_to :lexeme

  validates :surface, :context_translation, presence: true
  validates :start_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :end_offset, numericality: { only_integer: true, greater_than: :start_offset }
  validates :politeness, inclusion: { in: POLITENESS }, allow_nil: true
  validate :offsets_match_surface

  # Offsets are codepoints, so Ruby's String#[] and JS Array.from(text) agree for Hangul and emoji.
  def self.locate(text, surface, from: 0)
    start = text.index(surface, from)
    start && [ start, start + surface.length ]
  end

  private
    # LLMs often get offsets wrong; the slice of the bubble text must be exactly the surface.
    def offsets_match_surface
      return unless bubble && start_offset && end_offset

      slice = bubble.text[start_offset...end_offset]
      return if slice == surface

      errors.add(:surface, "#{surface.inspect} does not match text[#{start_offset}...#{end_offset}] = #{slice.inspect}")
    end
end
