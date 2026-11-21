module Ai
  # Speech-to-text for "story by voice" (7.12): Ai::Stt::LlmAudio (a multimodal model on OpenRouter) and the fake.
  module Stt
    Result = Data.define(:text, :language, :usage, :cost_usd, :duration_ms, :provider, :model)
  end
end
