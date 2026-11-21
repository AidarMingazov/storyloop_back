# "Report" in the reader (7.6). An open report takes the story out of the community feed until a
# moderator decides (Stories.reports_to_hide); the reporter stops seeing it at once.
class Report < ApplicationRecord
  REASONS = %w[sexual violence hate spam copyright personal other].freeze

  belongs_to :reporter, class_name: "User"
  belongs_to :episode
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :reason, REASONS.index_by(&:itself), validate: true
  # resolved — the moderator hid the story; dismissed — the story was fine and came back.
  enum :status, { open: "open", resolved: "resolved", dismissed: "dismissed" }, default: :open, validate: true

  validates :comment, length: { maximum: 1000 }
  validates :episode_id, uniqueness: { scope: :reporter_id }

  after_create_commit :pull_from_feed

  def self.close_all(episodes, as:, by:)
    where(episode: episodes).open.update_all(status: as, resolved_by_id: by.id, resolved_at: Time.current, updated_at: Time.current)
  end

  private
    def pull_from_feed
      series = episode.series
      return unless series.user_story? && series.approved?
      series.pending! if Report.open.where(episode: series.episodes).count >= Stories.reports_to_hide
    end
end
