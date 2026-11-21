module Ai
  module Tts
    # MiniMax T2A v2 (speech-2.8-turbo / -hd). Voices: platform.minimax.io/docs/faq/system-voice-id (Korean_* etc.).
    #   speak(text: "안녕하세요", voice: "Korean_SweetGirl", language: "ko", speed: 1.0, emotion: "happy")
    # Billed by extra_info.usage_characters (Korean: 1 character = 1). Errors come in base_resp with HTTP 200.
    class Minimax
      LANGUAGES = { "ko" => "Korean", "en" => "English", "ja" => "Japanese", "zh" => "Chinese", "ru" => "Russian",
                    "es" => "Spanish", "fr" => "French", "de" => "German", "it" => "Italian", "pt" => "Portuguese" }.freeze
      EMOTIONS = %w[happy sad angry fearful disgusted surprised calm].freeze
      ERRORS = { 1002 => RateLimited, 1004 => Unauthorized, 1008 => InsufficientBalance, 1026 => ContentRejected,
                 1027 => ContentRejected, 1039 => RateLimited }.freeze

      attr_reader :provider, :model

      def initialize(provider:, model:, settings:, api_key:, http:)
        @provider = provider
        @model = model
        @settings = settings
        @api_key = api_key
        @http = http
      end

      def speak(text:, voice:, language: nil, speed: 1.0, emotion: nil, format: "mp3")
        voice_setting = { voice_id: voice, speed: speed.to_f.clamp(0.5, 2.0), vol: 1, pitch: 0 }
        voice_setting[:emotion] = emotion.to_s if EMOTIONS.include?(emotion.to_s)
        body = { model:, text:, stream: false, output_format: "hex", voice_setting:,
                 audio_setting: { sample_rate: 32_000, bitrate: 128_000, format:, channel: 1 } }
        body[:language_boost] = LANGUAGES[language.to_s] if LANGUAGES.key?(language.to_s)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        data = @http.post_json("#{@settings.fetch('base_url')}/v1/t2a_v2", body,
                               headers: { "Authorization" => "Bearer #{@api_key}" }, timeout: @settings.fetch("timeout", 120))
        check!(data)
        hex = data.dig("data", "audio").presence || raise(InvalidResponse.new("#{provider}: empty audio", provider:))
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        info = data["extra_info"] || {}
        characters = info["usage_characters"] || text.length

        Ai.record Result.new(
          audio: StringIO.new([ hex ].pack("H*")), content_type: format == "mp3" ? "audio/mpeg" : "audio/#{format}",
          audio_ms: info["audio_length"].to_i, usage: Usage.new(characters:),
          cost_usd: Pricing.tts(provider:, model:, characters:), duration_ms:, provider:, model:
        )
      end

      private

      def check!(data)
        code = data.dig("base_resp", "status_code").to_i
        return if code.zero?

        message = data.dig("base_resp", "status_msg")
        raise ERRORS.fetch(code, ProviderError).new("#{provider}: #{code} #{message}", provider:, status: code,
                                                     body: data.except("data").to_json[0, 2000])
      end
    end
  end
end
