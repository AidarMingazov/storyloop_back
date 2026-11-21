module Ai
  module Stt
    # Offline speech-to-text: returns the scripted text (respond_with "…") or a fixed sentence.
    class Fake
      DEFAULT_TEXT = "A story about two friends who get lost in Seoul."

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

      # audio: IO, blob or attachable; language: ISO code or nil (auto).
      def transcribe(audio:, language: nil)
        self.class.calls << { step:, language:, audio: audio.class.name }
        item = self.class.responses.shift
        raise item if item.is_a?(Exception)

        Ai.record Result.new(text: item || DEFAULT_TEXT, language: language || "en", usage: Usage.new,
                             cost_usd: 0.0, duration_ms: 0, provider:, model:)
      end
    end
  end
end
