# The brief for generating one user story (7.3) — the input of Stories::Generator (7.4) and what the free-generation
# limit counts (7.5). The series and its episode #1 exist from the start, so "My stories" and the share link work
# while the story is being generated. A comic from photos (7.11) stops halfway: the author confirms the characters
# drawn from the photos ("confirming"), then generation goes on. The photos themselves are deleted when it ends.
class StoryRequest < ApplicationRecord
  MODES = %w[theme idea text surprise photos].freeze
  PROMPT_LIMITS = { "idea" => 500, "text" => 3000, "photos" => 500 }.freeze
  LEVELS = Cefr::LEVELS.first(4)
  FORMATS = %w[webtoon chat].freeze
  # Steps the status page shows, in order (a subset of GenerationLog::STEPS; a generator may skip some).
  STEPS = %w[script images layout tokens audio].freeze
  PHOTO_STEPS = %w[vision sheets].freeze
  PHOTO_LIMIT = 10
  PHOTO_BYTES = 10.megabytes
  PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze
  PHOTO_CHARACTERS = 3 # people and animals that become characters
  REDRAWS = 5          # sheet redraws per story on the confirmation screen
  # Default voices on the confirmation screen; the author can switch.
  VOICES = { "female" => { "ko" => "Korean_SweetGirl", "en" => "English_SentimentalLady" },
             "male" => { "ko" => "Korean_ReliableYouth", "en" => "English_DecentYoungMan" } }.freeze

  belongs_to :user
  belongs_to :series
  belongs_to :episode
  belongs_to :language_pair
  has_many_attached :photos

  enum :mode, MODES.index_by(&:itself), validate: true, prefix: true
  enum :status, { queued: "queued", running: "running", confirming: "confirming", succeeded: "succeeded", failed: "failed" },
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

  def steps = mode_photos? ? PHOTO_STEPS + STEPS : STEPS

  # Photos still waiting for the author's confirmation of the characters.
  def awaiting_confirmation? = mode_photos? && confirmed_at.nil?

  def start!
    update!(status: :running, started_at: Time.current, error: nil, rejection: nil)
    episode.generating!
  end

  def progress!(step) = update!(step: step)

  # Characters from the photos are drawn: the author looks at them (stories/_confirm).
  def await_confirmation!
    update!(status: :confirming, step: nil)
  end

  # names / voices: {character_id => value} from the confirmation screen.
  def confirm!(names: {}, voices: {})
    lang = language_pair.target_lang
    transaction do
      series.characters.each do |character|
        name = names[character.id.to_s].to_s.squish
        voice = VOICES.dig(voices[character.id.to_s].to_s, lang)
        character.update!(name: (name.match?(Stories::Script::NAME) ? name : character.name), voice: voice || character.voice)
      end
      update!(status: :queued, confirmed_at: Time.current)
    end
  end

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

  # A photo as a JPEG for the AI providers: at most 1600 px, rotated by EXIF and stripped of it (location, device).
  def photo_jpeg(index)
    photo = photos_attachments.order(:id)[index] or return
    photo.variant(resize_to_limit: [ 1600, 1600 ], format: :jpeg, saver: { quality: 85, strip: true }).processed.download
  end

  # Originals are kept only while they are needed (generation, sheet redraws).
  def purge_photos!
    photos.purge_later if photos.attached?
  end

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
