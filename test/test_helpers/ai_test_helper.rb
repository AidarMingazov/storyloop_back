# Offline helpers for Ai::* adapters: a scripted HTTP transport and live-provider config without the fakes.
module AiTestHelper
  # Returns queued responses in order (an Exception instance is raised instead) and keeps every request.
  class FakeTransport
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def call(request)
      @requests << request
      response = @responses.shift || raise("FakeTransport: no response queued for #{request.method} #{request.url}")
      raise response if response.is_a?(Exception)

      response
    end

    def json_body(index = -1) = JSON.parse(requests[index].body)
  end

  def self.included(base)
    base.setup { Ai.reset_fakes! }
    base.teardown { Ai.config = nil }
  end

  def json_response(hash, status: 200, headers: {})
    Ai::Http::Response.new(status:, body: hash.to_json, headers:)
  end

  def raw_response(body, status: 200, headers: {})
    Ai::Http::Response.new(status:, body:, headers:)
  end

  def sleeps = @sleeps ||= []

  def ai_http(transport, provider: "test", retries: 2)
    Ai::Http.new(provider:, transport:, retries:, sleeper: ->(seconds) { sleeps << seconds })
  end

  # Real providers from config/ai.yml (no force_provider), keys from the given ENV.
  def with_live_ai(env = {})
    Ai.config = Ai::Config.new(Rails.application.config_for(:ai).except(:force_provider))
    previous = env.keys.to_h { |key| [ key, ENV[key] ] }
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous&.each { |key, value| ENV[key] = value }
    Ai.config = nil
  end
end
