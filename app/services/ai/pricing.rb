module Ai
  # Cost of a call in USD from the prices in config/ai.yml. Unknown model → 0 (logged as a warning).
  module Pricing
    module_function

    def llm(provider:, model:, usage:, at: Time.current)
      price = lookup(provider, model)
      return 0.0 if price.empty?

      fresh = [ usage.input_tokens - usage.cached_tokens, 0 ].max
      cost = (fresh * price["input"].to_f) +
             (usage.cached_tokens * price.fetch("input_cached", price["input"]).to_f) +
             (usage.output_tokens * price["output"].to_f)
      cost / 1_000_000 * factor(provider, at)
    end

    def image(provider:, model:, images:, references: 0)
      price = lookup(provider, model)
      return 0.0 if price.empty?

      paid_references = [ references - price.fetch("free_references", 0).to_i, 0 ].max
      (images * price["image"].to_f) + (images.positive? ? paid_references * price["reference"].to_f : 0)
    end

    def tts(provider:, model:, characters:)
      price = lookup(provider, model)
      return 0.0 if price.empty?

      characters * price["per_million_characters"].to_f / 1_000_000
    end

    # DeepSeek: half price outside peak hours (UTC) and on weekends.
    def factor(provider, at)
      off_peak = Ai.config.off_peak(provider)
      return 1.0 unless off_peak

      utc = at.utc
      weekend = utc.saturday? || utc.sunday?
      peak = off_peak.fetch("peak_hours_utc", []).any? { |from, to| (from...to).cover?(utc.hour) }
      peak && !(weekend && off_peak["weekdays_only"]) ? 1.0 : off_peak.fetch("factor", 1.0).to_f
    end

    def lookup(provider, model)
      Ai.config.price(provider, model).tap do |price|
        Rails.logger.warn("[ai] no price for #{provider}/#{model} in config/ai.yml") if price.empty?
      end
    end
  end
end
