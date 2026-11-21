module Ai
  # Speech-to-text for "story by voice" (7.12). Only the interface and the fake exist; the provider is chosen later.
  module Stt
    Result = Data.define(:text, :language, :usage, :cost_usd, :duration_ms, :provider, :model)
  end
end
