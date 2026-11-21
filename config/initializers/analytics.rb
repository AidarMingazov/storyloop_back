# PostHog: project API key (public, "phc_…") and host from credentials or ENV.
#   bin/rails credentials:edit → posthog: { api_key: phc_…, host: https://eu.i.posthog.com }
posthog = Rails.application.credentials.posthog || {}
Rails.application.config.x.posthog = {
  api_key: posthog[:api_key] || ENV["POSTHOG_API_KEY"],
  host: posthog[:host] || ENV.fetch("POSTHOG_HOST", "https://eu.i.posthog.com")
}

# to_prepare (not after_initialize): Analytics lives in app/ and is reloaded in development,
# which would drop a backend that was set only once at boot.
Rails.application.config.to_prepare do
  config = Rails.application.config.x.posthog
  Analytics.backend ||=
    if Rails.env.test? then Analytics::MemoryBackend.new
    elsif config[:api_key].present? then Analytics::PosthogBackend.new(api_key: config[:api_key], host: config[:host])
    else Analytics::LogBackend.new
    end
end
