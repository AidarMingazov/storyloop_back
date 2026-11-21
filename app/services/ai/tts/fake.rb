module Ai
  module Tts
    # Offline TTS: a short silent WAV (~60 ms of audio per character, at least 0.5 s). Calls kept in Fake.calls.
    class Fake
      SAMPLE_RATE = 8_000

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

      def speak(text:, voice:, language: nil, speed: 1.0, emotion: nil, format: "wav")
        self.class.calls << { step:, text:, voice:, language:, speed:, emotion: }
        item = self.class.responses.shift
        raise item if item.is_a?(Exception)

        audio_ms = [ text.to_s.length * 60, 500 ].max
        Ai.record Result.new(
          audio: StringIO.new(silent_wav(audio_ms)), content_type: "audio/wav", audio_ms:,
          usage: Usage.new(characters: text.to_s.length), cost_usd: 0.0, duration_ms: 0, provider:, model:
        )
      end

      private

      def silent_wav(ms)
        samples = SAMPLE_RATE * ms / 1000
        data = "\x80".b * samples # 8-bit unsigned PCM silence
        [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE, 1, 8, "data", data.bytesize ]
          .pack("a4Va4a4VvvVVvva4V") + data
      end
    end
  end
end
