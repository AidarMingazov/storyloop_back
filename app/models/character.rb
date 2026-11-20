class Character < ApplicationRecord
  belongs_to :series
  has_many :bubbles, dependent: :nullify
  has_one_attached :avatar
  has_many_attached :reference_images

  validates :name, presence: true
  validates :key, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, uniqueness: { scope: :series_id }
end
