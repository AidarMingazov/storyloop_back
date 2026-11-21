module Ai
  module Llm
    # Chat Completions API: DeepSeek directly, OpenRouter (Claude, Gemini, Qwen, DeepSeek…).
    #   chat([{ role: "system", content: "…" }, { role: "user", content: "…" }], json: true, images: [blob, "https://…"])
    # images are attached to the last user message (vision models).
    class OpenaiCompatible
      attr_reader :provider, :model

      def initialize(provider:, model:, settings:, api_key:, http:)
        @provider = provider
        @model = model
        @settings = settings
        @api_key = api_key
        @http = http
      end

      def chat(messages, json: false, images: [], max_tokens: 8_000, temperature: 0.7)
        body = { model:, messages: with_images(messages, images), max_tokens:, temperature: }
        body[:response_format] = { type: "json_object" } if json
        body[:usage] = { include: true } if @settings["reports_cost"]

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        data = @http.post_json("#{@settings.fetch('base_url')}/chat/completions", body,
                               headers: { "Authorization" => "Bearer #{@api_key}" },
                               timeout: @settings.fetch("timeout", 300))
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

        choice = data.dig("choices", 0) || raise(error(data))
        text = choice.dig("message", "content").to_s
        parsed, json_error = json ? Llm.parse_json(text) : [ nil, nil ]
        usage = usage_from(data["usage"] || {})

        Ai.record Result.new(
          text:, json: parsed, json_error:, finish_reason: choice["finish_reason"], usage:,
          cost_usd: cost(data["usage"], usage), duration_ms:, provider:, model: data["model"].presence || model
        )
      end

      private

      def with_images(messages, images)
        messages = messages.map { |m| m.to_h.symbolize_keys }
        return messages if images.blank?

        index = messages.rindex { |m| m[:role].to_s == "user" } || raise(ArgumentError, "images need a user message")
        text = messages[index][:content]
        parts = text.is_a?(Array) ? text : [ { type: "text", text: text.to_s } ]
        parts += images.map { |image| { type: "image_url", image_url: { url: DataUri.call(image) } } }
        messages[index] = messages[index].merge(content: parts)
        messages
      end

      def usage_from(raw)
        Usage.new(
          input_tokens: raw["prompt_tokens"], output_tokens: raw["completion_tokens"],
          cached_tokens: raw["prompt_cache_hit_tokens"] || raw.dig("prompt_tokens_details", "cached_tokens"),
          reasoning_tokens: raw.dig("completion_tokens_details", "reasoning_tokens")
        )
      end

      def cost(raw, usage)
        reported = raw&.dig("cost")
        return reported.to_f if reported

        Pricing.llm(provider:, model:, usage:)
      end

      def error(data)
        InvalidResponse.new("#{provider}: no choices in response: #{data.to_json[0, 300]}", provider:, body: data.to_json[0, 2000])
      end
    end
  end
end
