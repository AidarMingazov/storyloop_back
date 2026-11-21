module Ai
  module Steps
    # LLM call of a pipeline step with one switch to the step's fallback model when the main provider fails after its
    # HTTP retries (down, out of money, rate limited). Content refusals are not retried elsewhere.
    module FallbackChat
      private
        def chat(step, messages, **options)
          @llm ||= Ai.llm(step)
          @llm.chat(messages, **options)
        rescue ProviderError => e
          raise if @fell_back || e.is_a?(ContentRejected)

          Rails.logger.warn("[ai] #{step}: #{e.class}: #{e.message.truncate(200)} — switching to the fallback model")
          @fell_back = true
          @llm = Ai.llm(step, fallback: true)
          retry
        end
    end
  end
end
