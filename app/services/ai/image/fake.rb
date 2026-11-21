module Ai
  module Image
    # Offline image generator: the reader's placeholder scene (webp), deterministic per prompt.
    # Ai::Image::Fake.calls keeps prompts and reference counts; respond_with(Ai::ContentRejected.new("…")) to fail.
    class Fake
      class << self
        def responses = @responses ||= []
        def calls = @calls ||= []
        def respond_with(*items) = responses.concat(items)

        def reset!
          @responses = []
          @calls = []
        end
      end

      attr_reader :step, :model

      def initialize(step:, model: nil)
        @step = step
        @model = model || "fake"
      end

      def provider = "fake"

      def generate(prompt:, references: [], size: "1728x2160")
        self.class.calls << { step:, prompt:, references: Array(references).size, size: }
        item = self.class.responses.shift
        raise item if item.is_a?(Exception)

        width, height = size.to_s.split("x").map(&:to_i)
        aspect = width.to_i.positive? && height.to_i.positive? ? width.to_f / height : 0.8
        bytes = Episodes::PlaceholderImage.render(aspect, prompt.to_s.sum)
        Ai.record Result.new(
          images: [ Generated.new(io: StringIO.new(bytes), content_type: "image/webp", filename: "image-1.webp") ],
          usage: Usage.new(images: 1), cost_usd: 0.0, duration_ms: 0, provider:, model:
        )
      end
    end
  end
end
