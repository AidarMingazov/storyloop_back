module Ai
  module Stt
    # Speech-to-text through a multimodal chat model (Gemini Flash on OpenRouter, the same key as the LLM steps): the
    # recording goes in as input_audio, the model writes down the words. "Story by voice" (7.12) sends a short WAV
    # recorded in the browser. Cost: what OpenRouter reports, else the LLM prices of the key's provider.
    class LlmAudio
      FORMATS = { "audio/wav" => "wav", "audio/x-wav" => "wav", "audio/wave" => "wav", "audio/mpeg" => "mp3", "audio/mp3" => "mp3" }.freeze
      PROMPT = "Transcribe this voice note word for word, in the language it is spoken%s. Return only the spoken words " \
               "with normal punctuation — no comments, no quotes, no translation. If there is no speech, return nothing."

      attr_reader :provider, :model

      def initialize(provider:, model:, settings:, api_key:, http:)
        @provider = provider
        @model = model
        @settings = settings
        @api_key = api_key
        @http = http
      end

      # audio: an uploaded file, IO, path or blob; language: ISO code hint or nil (any language).
      def transcribe(audio:, language: nil)
        bytes, content_type = read(audio)
        format = FORMATS.fetch(content_type.to_s.split(";").first) { raise ArgumentError, "unsupported audio type #{content_type.inspect}" }
        body = { model:, temperature: 0, max_tokens: 2_000, messages: [ { role: "user", content: [
          { type: "text", text: format(PROMPT, language ? " (probably #{language})" : "") },
          { type: "input_audio", input_audio: { data: Base64.strict_encode64(bytes), format: } }
        ] } ] }
        body[:usage] = { include: true } if @settings["reports_cost"]

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        data = @http.post_json("#{@settings.fetch('base_url')}/chat/completions", body,
                               headers: { "Authorization" => "Bearer #{@api_key}" }, timeout: @settings.fetch("timeout", 120))
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        text = data.dig("choices", 0, "message", "content")
        raise InvalidResponse.new("#{provider}: no transcript: #{data.to_json[0, 300]}", provider:) if text.nil?

        raw = data["usage"] || {}
        usage = Usage.new(input_tokens: raw["prompt_tokens"], output_tokens: raw["completion_tokens"])
        cost = raw["cost"]&.to_f || Pricing.llm(provider: @settings.fetch("key_of", provider), model:, usage:)
        Ai.record Result.new(text: text.to_s.strip, language:, usage:, cost_usd: cost, duration_ms:, provider:,
                             model: data["model"].presence || model)
      end

      private
        def read(audio)
          case audio
          when ActiveStorage::Blob then [ audio.download, audio.content_type ]
          when String, Pathname then [ File.binread(audio), Marcel::MimeType.for(Pathname(audio)) ]
          else
            audio.rewind if audio.respond_to?(:rewind)
            [ audio.read, audio.try(:content_type) || Marcel::MimeType.for(audio) ]
          end
        end
    end
  end
end
