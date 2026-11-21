module Ai
  module Llm
    # Offline LLM for tests and local runs without keys. Scripted answers are used in order:
    #   Ai::Llm::Fake.respond_with({ "episode" => {…} }, "plain text", Ai::RateLimited.new("busy"))
    # Without a script: "{}" for json: true, "ok" otherwise. Every call is kept in Ai::Llm::Fake.calls.
    class Fake
      # An answer cut off by max_tokens: respond_with(Ai::Llm::Fake::CutOff.new('{"bubbles": ['))
      CutOff = Data.define(:text)

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

      def chat(messages, json: false, images: [], **options)
        self.class.calls << { step:, messages:, json:, images: images.size, **options }
        item = self.class.responses.shift
        raise item if item.is_a?(Exception)

        text = case item
        when nil then json ? "{}" : "ok"
        when String then item
        when CutOff then item.text
        else JSON.generate(item)
        end
        parsed, json_error = json ? Llm.parse_json(text) : [ nil, nil ]
        input = messages.sum { |m| m.to_h.symbolize_keys[:content].to_s.length } / 4

        Ai.record Result.new(
          text:, json: parsed, json_error:, finish_reason: item.is_a?(CutOff) ? "length" : "stop",
          usage: Usage.new(input_tokens: input, output_tokens: text.length / 4),
          cost_usd: 0.0, duration_ms: 0, provider:, model:
        )
      end
    end
  end
end
