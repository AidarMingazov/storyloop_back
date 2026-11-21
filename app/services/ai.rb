# Adapters to AI providers for the content pipeline. The provider of each step comes from config/ai.yml:
#
#   Ai.llm(:script).chat(messages, json: true)          # → Ai::Llm::Result
#   Ai.image(:images).generate(prompt:, references: [])  # → Ai::Image::Result
#   Ai.tts(:audio).speak(text:, voice:, language: "ko")  # → Ai::Tts::Result
#   Ai.stt(:stt).transcribe(audio:, language: "ko")      # → Ai::Stt::Result
#
# Every call is added to the GenerationLog opened by GenerationLog.track (tokens, images, characters, cost).
module Ai
  class Error < StandardError; end
  class ConfigError < Error; end

  # Raised for anything the provider refused or failed to do. Never contains the API key.
  class ProviderError < Error
    attr_reader :provider, :status, :body

    def initialize(message = nil, provider: nil, status: nil, body: nil)
      @provider = provider
      @status = status
      @body = body
      super(message)
    end
  end

  class RateLimited < ProviderError; end
  class InsufficientBalance < ProviderError; end
  class Unauthorized < ProviderError; end
  class InvalidResponse < ProviderError; end
  # The provider's safety filter rejected the input or the output (photos, prompts, text).
  class ContentRejected < ProviderError; end

  # Token / unit counters of one call. Every adapter fills what applies.
  Usage = Data.define(:input_tokens, :output_tokens, :cached_tokens, :reasoning_tokens, :images, :characters) do
    def initialize(input_tokens: 0, output_tokens: 0, cached_tokens: 0, reasoning_tokens: 0, images: 0, characters: 0)
      super(input_tokens: input_tokens.to_i, output_tokens: output_tokens.to_i, cached_tokens: cached_tokens.to_i,
            reasoning_tokens: reasoning_tokens.to_i, images: images.to_i, characters: characters.to_i)
    end
  end

  FAKES = { llm: "Ai::Llm::Fake", image: "Ai::Image::Fake", tts: "Ai::Tts::Fake", stt: "Ai::Stt::Fake" }.freeze
  LOG_KEY = :ai_generation_log

  class << self
    attr_writer :config

    def config = @config ||= Config.load

    def llm(step, fallback: false) = build(:llm, step, fallback:)
    def image(step, fallback: false) = build(:image, step, fallback:)
    def tts(step, fallback: false) = build(:tts, step, fallback:)
    def stt(step, fallback: false) = build(:stt, step, fallback:)

    # Adds a finished call to the GenerationLog of the current GenerationLog.track block, if any.
    def record(result)
      ActiveSupport::IsolatedExecutionState[LOG_KEY]&.add_call(result)
      result
    end

    def current_log = ActiveSupport::IsolatedExecutionState[LOG_KEY]

    def with_log(log)
      previous = ActiveSupport::IsolatedExecutionState[LOG_KEY]
      ActiveSupport::IsolatedExecutionState[LOG_KEY] = log
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[LOG_KEY] = previous
    end

    def reset_fakes!
      FAKES.each_value { |name| name.constantize.reset! }
    end

    private

    def build(kind, step, fallback:)
      settings = config.step(step)
      settings = settings.fetch("fallback") { raise ConfigError, "no fallback for step #{step}" } if fallback
      provider = config.forced_provider || settings.fetch("provider")
      model = settings["model"]
      return FAKES.fetch(kind).constantize.new(step: step.to_s, model:) if provider == "fake"

      provider_settings = config.provider(provider)
      unless provider_settings["kind"] == kind.to_s
        raise ConfigError, "provider #{provider} is #{provider_settings['kind']}, step #{step} needs #{kind}"
      end

      provider_settings.fetch("adapter").constantize.new(
        provider:, model:, settings: provider_settings, api_key: config.api_key(provider),
        http: Http.new(provider:)
      )
    end
  end
end
