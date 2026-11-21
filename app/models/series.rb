class Series < ApplicationRecord
  belongs_to :language_pair
  belongs_to :author, class_name: "User", optional: true
  has_many :characters, dependent: :destroy
  has_many :episodes, -> { order(:number) }, dependent: :destroy
  has_many :story_requests, dependent: :delete_all
  has_one_attached :cover

  enum :status, { draft: "draft", published: "published", archived: "archived" }, default: :draft, validate: true
  # catalog — made by the team; user — a story made by a learner (wave 7).
  enum :source, { catalog: "catalog", user: "user" }, default: :catalog, validate: true, prefix: true
  # Who can open a user story: only the author / anyone with the link / everyone, and it is in the feed.
  enum :visibility, { private: "private", link: "link", public: "public" }, default: :public, validate: true, prefix: true
  # pending — waiting for a check or for a moderator after a report; hidden — removed by moderation.
  enum :moderation_state, { pending: "pending", approved: "approved", hidden: "hidden" }, default: :approved, validate: true

  validates :title, presence: true
  validates :slug, presence: true, format: { with: /\A[a-z0-9-]+\z/ }, uniqueness: { scope: :language_pair_id }
  validates :cefr_level, inclusion: { in: Cefr::LEVELS }
  validates :author, presence: true, if: :source_user?

  scope :ordered, -> { order(:position, :id) }
  scope :catalog, -> { source_catalog }
  # User stories everyone may find: in the community feed and on the author's page.
  scope :listed, -> { source_user.visibility_public.approved.published.where(author_id: User.not_banned.select(:id)) }

  def user_story? = source_user?

  def listed?
    user_story? && visibility_public? && approved? && published? && !author&.banned?
  end
end
