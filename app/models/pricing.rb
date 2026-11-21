# Paywall plans per language pair (config/pricing.yml). Display strings only: real prices live in
# Stripe once PAYMENTS_MODE=stripe (wave 7).
module Pricing
  PLANS = %w[yearly monthly].freeze

  module_function

  def config
    @config ||= JSON.parse(Rails.application.config_for(:pricing).to_json) # plain string-keyed hashes
  end

  def for(pair)
    config.fetch(pair.code, config.fetch("default"))
  end

  def mode
    ENV.fetch("PAYMENTS_MODE", "fake_door")
  end

  def fake_door? = mode == "fake_door"
end
