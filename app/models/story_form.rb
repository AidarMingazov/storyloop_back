# "Create a story" (7.3): validates the brief and creates the series + episode #1 (status generating) +
# StoryRequest in one go. The job does the rest, moderation of the brief included (7.6).
class StoryForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  TEXT_FILE_LIMIT = 20.kilobytes
  VISIBILITIES = %w[private link public].freeze

  attribute :mode, :string, default: "theme"
  attribute :theme, :string
  attribute :cast, :string # empty: Stories::Cast.for picks one (theme, random for surprise, everyday)
  attribute :prompt, :string
  attribute :text_file
  attribute :pair, :string
  attribute :cefr_level, :string, default: "A1"
  attribute :format, :string, default: "webtoon"
  attribute :visibility, :string, default: "link"
  attribute :display_name, :string
  attribute :rules_accepted, :boolean, default: false

  attr_accessor :user
  attr_reader :story_request

  validates :mode, inclusion: { in: StoryRequest::MODES }
  validates :theme, inclusion: { in: ->(_) { Stories::Themes.keys } }, if: -> { mode == "theme" }
  validates :cast, inclusion: { in: ->(_) { Stories::Cast.keys } }, allow_blank: true
  validates :prompt, presence: true, if: -> { mode.in?(%w[idea text]) }
  validates :cefr_level, inclusion: { in: StoryRequest::LEVELS }
  validates :format, inclusion: { in: StoryRequest::FORMATS }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :display_name, length: { maximum: 40 }
  validates :rules_accepted, acceptance: { accept: true }
  validate :pair_active, :prompt_fits, :text_file_readable

  def self.model_name = ActiveModel::Name.new(self, nil, "Story")

  def language_pair
    @language_pair ||= LanguagePair.active.find_by(code: pair)
  end

  # → StoryRequest, or nil with errors
  def submit
    read_text_file
    return unless valid?

    ActiveRecord::Base.transaction do
      user.update!(display_name: display_name) if display_name.present? && user.display_name.blank?
      series = Series.create!(source: :user, author: user, language_pair: language_pair, slug: "u-#{SecureRandom.base36(10)}",
                              title: placeholder_title, genre: theme, cefr_level: cefr_level, visibility: visibility,
                              moderation_state: :pending)
      episode = series.episodes.create!(number: 1, title: placeholder_title, format: format, cefr_level: cefr_level,
                                        status: :generating, free: true)
      @story_request = StoryRequest.create!(user: user, series: series, episode: episode, language_pair: language_pair,
                                            mode: mode, theme: (theme if mode == "theme"), prompt: prompt.presence,
                                            cefr_level: cefr_level, format: format,
                                            cast_key: Stories::Cast.for(mode:, theme:, cast:).key)
    end
  end

  private
    def prompt_text = mode.in?(%w[idea text]) ? prompt.to_s.strip : ""

    # Shown while the story is generated; the generator sets the real one.
    def placeholder_title
      case mode
      when "theme" then Stories::Themes.title(theme)
      when "surprise" then I18n.t("stories.new.surprise_title")
      else prompt_text.lines.first.to_s.squish.truncate(60)
      end
    end

    # A .txt upload fills "own text" when the text area is empty.
    def read_text_file
      return unless mode == "text" && text_file.respond_to?(:read) && prompt.blank?
      return errors.add(:text_file, :too_big) if text_file.size > TEXT_FILE_LIMIT

      self.prompt = text_file.read.force_encoding(Encoding::UTF_8).scrub("").strip
    end

    def text_file_readable
      return unless text_file.respond_to?(:content_type)
      errors.add(:text_file, :invalid) unless text_file.content_type.to_s.start_with?("text/plain")
    end

    def pair_active
      errors.add(:pair, :inclusion) unless language_pair
    end

    def prompt_fits
      limit = StoryRequest::PROMPT_LIMITS[mode]
      errors.add(:prompt, :too_long, count: limit) if limit && prompt_text.length > limit
    end
end
