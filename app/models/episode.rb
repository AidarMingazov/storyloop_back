class Episode < ApplicationRecord
  FORMATS = %w[webtoon manga chat illustrated].freeze

  belongs_to :series
  has_one :language_pair, through: :series
  has_many :panels, -> { order(:position) }, dependent: :destroy
  has_many :bubbles, through: :panels
  has_many :tokens, through: :bubbles
  has_many :reading_progresses, dependent: :destroy
  has_many :generation_logs, dependent: :nullify

  enum :format, FORMATS.index_by(&:itself), validate: true, prefix: :format
  enum :status, { draft: "draft", generating: "generating", review: "review", published: "published" },
       default: :draft, validate: true

  validates :title, presence: true
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :series_id }
  validates :cefr_level, inclusion: { in: Cefr::LEVELS }

  before_save :stamp_published_at

  def publish!
    update!(status: :published)
  end

  def next_episode
    series.episodes.published.where("number > ?", number).first
  end

  def cost_usd
    generation_logs.sum(:cost_usd)
  end

  private
    def stamp_published_at
      self.published_at ||= Time.current if published?
    end
end
