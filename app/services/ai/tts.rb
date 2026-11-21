module Ai
  module Tts
    # audio: StringIO ready to attach; audio_ms: length of the speech; duration_ms: time the call took.
    Result = Data.define(:audio, :content_type, :audio_ms, :usage, :cost_usd, :duration_ms, :provider, :model) do
      def to_attachable(filename) = { io: audio, filename:, content_type: }
    end
  end
end
