class Series < ApplicationRecord
  belongs_to :language_pair
  has_many :characters, dependent: :destroy
  has_many :episodes, -> { order(:number) }, dependent: :destroy
  has_one_attached :cover

  enum :status, { draft: "draft", published: "published", archived: "archived" }, default: :draft, validate: true

  validates :title, presence: true
  validates :slug, presence: true, format: { with: /\A[a-z0-9-]+\z/ }, uniqueness: { scope: :language_pair_id }
  validates :cefr_level, inclusion: { in: Cefr::LEVELS }

  scope :ordered, -> { order(:position, :id) }
end
