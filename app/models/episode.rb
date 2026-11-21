class Episode < ApplicationRecord
  FORMATS = %w[webtoon manga chat illustrated].freeze
  SHARE_TOKEN_LENGTH = 12 # base58 ≈ 70 bits: unguessable for "anyone with the link" stories

  belongs_to :series
  belongs_to :origin_episode, class_name: "Episode", optional: true # translated from (7.8)
  has_one :language_pair, through: :series
  has_many :panels, -> { order(:position) }, dependent: :destroy
  has_many :bubbles, through: :panels
  has_many :tokens, through: :bubbles
  has_many :reading_progresses, dependent: :destroy
  has_many :generation_logs, dependent: :nullify
  has_many :reports, dependent: :delete_all

  enum :format, FORMATS.index_by(&:itself), validate: true, prefix: :format
  # failed — a user story whose generation did not finish (wave 7).
  enum :status, { draft: "draft", generating: "generating", review: "review", published: "published", failed: "failed" },
       default: :draft, validate: true

  validates :title, presence: true
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :series_id }
  validates :cefr_level, inclusion: { in: Cefr::LEVELS }

  before_create :assign_share_token
  before_save :stamp_published_at

  delegate :user_story?, :author, to: :series

  def publish!
    update!(status: :published)
  end

  def next_episode
    series.episodes.published.where("number > ?", number).first
  end

  def cost_usd
    generation_logs.sum(:cost_usd)
  end

  # The old link stops working (e.g. it leaked); the story keeps its visibility.
  def reset_share_token!
    update!(share_token: self.class.generate_share_token)
  end

  def self.generate_share_token = SecureRandom.base58(SHARE_TOKEN_LENGTH)

  # Words saved from this episode and reads feed the "popular" sort of the community feed.
  def popularity = reads_count + (2 * saves_count)

  private
    def assign_share_token
      self.share_token ||= self.class.generate_share_token
    end

    def stamp_published_at
      self.published_at ||= Time.current if published?
    end
end
