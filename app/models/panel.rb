class Panel < ApplicationRecord
  DEFAULT_ASPECT_RATIO = 0.8

  belongs_to :episode
  has_many :bubbles, -> { order(:position) }, dependent: :destroy
  # WebP for phones: 800w for most screens, 1200w for 3x displays (served via srcset).
  has_one_attached :image do |image|
    image.variant :phone, resize_to_limit: [ 800, nil ], format: :webp, saver: { quality: 80 }, preprocessed: true
    image.variant :phone_2x, resize_to_limit: [ 1200, nil ], format: :webp, saver: { quality: 78 }, preprocessed: true
  end

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: :episode_id }

  # width / height of the panel image
  def aspect_ratio
    layout.fetch("aspect_ratio", DEFAULT_ASPECT_RATIO).to_f
  end
end
