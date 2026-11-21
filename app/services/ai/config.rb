module Ai
  # Reads config/ai.yml (steps, providers, prices) and API keys.
  class Config
    def self.load = new(Rails.application.config_for(:ai))

    def initialize(data)
      @data = data.to_h.deep_stringify_keys
    end

    def step(name)
      @data.dig("steps", name.to_s) || raise(ConfigError, "unknown AI step #{name.inspect} (config/ai.yml)")
    end

    def steps = @data.fetch("steps", {}).keys

    # "provider:model" pairs for the admin markup comparison (6.10).
    def comparison_models = @data.fetch("comparison_models", [])

    def provider(name)
      @data.dig("providers", name.to_s) || raise(ConfigError, "unknown AI provider #{name.inspect} (config/ai.yml)")
    end

    # Tests run every step on the fakes; AI_LIVE=1 turns real providers back on.
    def forced_provider
      @data["force_provider"].presence unless ENV["AI_LIVE"].present?
    end

    # credentials ai.<provider>_api_key, else ENV[<env>] (dev: storyloop_back/.env via compose env_file).
    def api_key(provider_name)
      settings = provider(provider_name)
      key = Rails.application.credentials.dig(:ai, :"#{provider_name}_api_key").presence
      key ||= ENV[settings["env"]].presence if settings["env"]
      key || raise(ConfigError, "no API key for #{provider_name}: credentials ai.#{provider_name}_api_key or ENV #{settings['env']}")
    end

    def price(provider_name, model)
      @data.dig("prices", provider_name.to_s, model.to_s) || {}
    end

    def off_peak(provider_name)
      @data.dig("prices", provider_name.to_s, "off_peak")
    end
  end
end
