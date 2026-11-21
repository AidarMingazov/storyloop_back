class LanguagePair < ApplicationRecord
  has_many :series, dependent: :restrict_with_error
  has_many :catalog_series, -> { catalog }, class_name: "Series", inverse_of: :language_pair # without user stories

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z]{2}-[a-z]{2}\z/ }
  validates :target_lang, :native_lang, presence: true
  validate :code_matches_languages

  scope :active, -> { where(active: true) }

  # Hints and the interface are shown in the learner's native language.
  def ui_locale = native_lang.to_sym

  def to_param = code

  private
    def code_matches_languages
      errors.add(:code, :invalid) unless code == "#{target_lang}-#{native_lang}"
    end
end
