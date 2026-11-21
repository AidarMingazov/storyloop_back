# Product analytics. Server-side events go through here; token_tapped and bubble_translated are
# captured in the browser by posthog-js (see analytics_controller.js) with the same distinct id.
module Analytics
  EVENTS = %w[
    landing_viewed onboarding_completed episode_started episode_completed token_tapped bubble_translated
    word_saved review_session_completed signup paywall_viewed checkout_clicked waitlist_email_submitted
    story_created story_ready story_failed story_published story_shared share_opened story_reported author_hidden
  ].freeze
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze

  mattr_accessor :backend

  def self.track(event, distinct_id:, properties: {})
    raise ArgumentError, "unknown analytics event #{event.inspect}" unless EVENTS.include?(event)
    return if distinct_id.blank?

    backend.capture(distinct_id: distinct_id.to_s, event: event, properties: properties.compact)
  end

  # Properties every event carries: pair, episode format and number, levels, UTM.
  def self.context(user: nil, episode: nil, utm: {})
    pair = episode&.series&.language_pair || user&.language_pair
    {
      pair: pair&.code,
      format: episode&.format,
      episode_number: episode&.number,
      episode_level: episode&.cefr_level,
      level: user&.self_level,
      guest: user&.guest?,
      ref: user&.referrer_id && user.referrer&.public_id # came through someone's share link (K-factor)
    }.merge((user&.utm.presence || utm || {}).slice(*UTM_KEYS).symbolize_keys).compact
  end

  class LogBackend
    def capture(**attrs)
      Rails.logger.info("[analytics] #{attrs.to_json}")
    end
  end

  class MemoryBackend
    attr_reader :events

    def initialize = @events = []
    def capture(**attrs) = @events << attrs
    def clear! = @events.clear
    def names = @events.map { |e| e[:event] }
  end

  class PosthogBackend
    def initialize(api_key:, host:)
      @client = PostHog::Client.new(api_key: api_key, host: host,
                                    on_error: ->(status, error) { Rails.logger.warn("[posthog] #{status} #{error}") })
    end

    def capture(**attrs)
      @client.capture(attrs)
    end
  end
end
