# The brief for generating one user story (7.3) — the input of Stories::Generator (wave 6, 7.4) and
# what the free-generation limit counts (7.5). The series and its episode #1 exist from the start,
# so "My stories" and the share link work while the story is being generated.
class StoryRequest < ApplicationRecord
  MODES = %w[theme idea text surprise].freeze # later: photos (7.11), voice (7.12)
  PROMPT_LIMITS = { "idea" => 500, "text" => 3000 }.freeze
  LEVELS = Cefr::LEVELS.first(4)
  FORMATS = %w[webtoon chat].freeze
  # Steps the status page shows, in order (a subset of GenerationLog::STEPS; a generator may skip some).
  STEPS = %w[script images layout tokens audio].freeze

  belongs_to :user
  belongs_to :series
  belongs_to :episode
  belongs_to :language_pair

  enum :mode, MODES.index_by(&:itself), validate: true, prefix: true
  enum :status, { queued: "queued", running: "running", succeeded: "succeeded", failed: "failed" },
       default: :queued, validate: true

  validates :cefr_level, inclusion: { in: LEVELS }
  validates :format, inclusion: { in: FORMATS }
  validates :theme, inclusion: { in: ->(_) { Stories::Themes.keys } }, if: :mode_theme?
  validates :prompt, presence: true, if: -> { mode_idea? || mode_text? }
  validate :prompt_fits

  # Generations that use up the free limit: a failed one is on us.
  scope :counted, -> { where.not(status: :failed) }

  after_update_commit :broadcast_status

  # Earlier briefs of the same author: "surprise me" uses them not to repeat itself (7.4).
  def previous_requests = user.story_requests.where.not(id: id).order(created_at: :desc).limit(20)

  def theme_title = Stories::Themes.title(theme)

  def start!
    update!(status: :running, started_at: Time.current, error: nil, rejection: nil)
    episode.generating!
  end

  def progress!(step) = update!(step: step)

  def succeed!
    update!(status: :succeeded, step: nil, finished_at: Time.current)
  end

  # Must work whatever state the records are in: it is the job's last word. rejection: the rule category when
  # moderation stopped the story (Stories::REJECTIONS) — the status page names it.
  def fail!(error, rejection: nil)
    transaction do
      assign_attributes(status: :failed, error: error.to_s.truncate(1000), rejection:, finished_at: Time.current)
      save!(validate: false)
      episode.update_column(:status, "failed")
    end
  end

  def duration = started_at && finished_at && (finished_at - started_at)

  private
    def prompt_fits
      limit = PROMPT_LIMITS[mode]
      errors.add(:prompt, :too_long, count: limit) if limit && prompt.to_s.length > limit
    end

    # The status page (stories/show) subscribes to this request.
    def broadcast_status
      I18n.with_locale(user.ui_locale || I18n.default_locale) do
        broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :status),
                                   partial: "stories/status", locals: { story_request: self }
      end
    end
end
