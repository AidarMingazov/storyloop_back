module Ai
  module Image
    # BytePlus ModelArk Seedream: text-to-image with up to 10–14 reference images (character sheets, place photos).
    #   generate(prompt: "…", references: [sheet_blob, place_photo], size: "1728x2160")
    # Images are downloaded right away: the URLs Seedream returns expire in 24 hours.
    class Seedream
      EXTENSIONS = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.freeze

      attr_reader :provider, :model

      def initialize(provider:, model:, settings:, api_key:, http:)
        @provider = provider
        @model = model
        @settings = settings
        @api_key = api_key
        @http = http
      end

      def generate(prompt:, references: [], size: "1728x2160")
        refs = Array(references).map { |ref| DataUri.call(ref) }
        body = { model:, prompt:, size:, response_format: "url", watermark: false }
        body[:image] = refs.one? ? refs.first : refs if refs.any?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        data = request(body)
        images = Array(data["data"]).each_with_index.filter_map { |item, i| download(item, i) }
        if images.empty?
          raise InvalidResponse.new("#{provider}: no images in response: #{data.to_json[0, 300]}", provider:, body: data.to_json[0, 2000])
        end

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Ai.record Result.new(
          images:, usage: Usage.new(images: images.size, output_tokens: data.dig("usage", "output_tokens")),
          cost_usd: Pricing.image(provider:, model:, images: images.size, references: refs.size),
          duration_ms:, provider:, model: data["model"].presence || model
        )
      end

      private

      def request(body)
        @http.post_json("#{@settings.fetch('base_url')}/images/generations", body,
                        headers: { "Authorization" => "Bearer #{@api_key}" }, timeout: @settings.fetch("timeout", 300))
      rescue ProviderError => e
        # Safety filter codes look like InputImageSensitiveContentDetected / OutputImageSensitiveContentDetected.
        raise unless e.body.to_s.match?(/Sensitive|ContentFilter|RiskControl/i)

        raise ContentRejected.new("#{provider}: rejected by the safety filter: #{e.body.to_s[0, 300]}",
                                  provider:, status: e.status, body: e.body)
      end

      def download(item, index)
        bytes = if item["b64_json"].present?
          Base64.decode64(item["b64_json"])
        elsif item["url"].present?
          @http.get(item["url"])
        end
        return unless bytes

        type = Marcel::MimeType.for(StringIO.new(bytes))
        Generated.new(io: StringIO.new(bytes), content_type: type, filename: "image-#{index + 1}.#{EXTENSIONS.fetch(type, 'jpg')}")
      end
    end
  end
end
