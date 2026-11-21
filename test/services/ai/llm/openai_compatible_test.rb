require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"

class Ai::Llm::OpenaiCompatibleTest < ActiveSupport::TestCase
  include AiTestHelper

  # Shapes captured from real DeepSeek / OpenRouter responses (script/ai_probe, 2026-11-21).
  DEEPSEEK = {
    "model" => "deepseek-flash",
    "choices" => [ { "finish_reason" => "stop", "message" => { "content" => '{"tokens": [{"surface": "짐이"}]}' } } ],
    "usage" => { "prompt_tokens" => 1_000, "completion_tokens" => 2_000, "prompt_cache_hit_tokens" => 200,
                 "completion_tokens_details" => { "reasoning_tokens" => 1_500 } }
  }.freeze
  OPENROUTER = {
    "model" => "anthropic/claude-haiku-5.5",
    "choices" => [ { "finish_reason" => "stop", "message" => { "content" => "```json\n{\"text\": \"a man on a beach\"}\n```" } } ],
    "usage" => { "prompt_tokens" => 3_289, "completion_tokens" => 1_972, "cost" => 0.00131,
                 "prompt_tokens_details" => { "cached_tokens" => 0 } }
  }.freeze

  def adapter(provider, transport, model:)
    settings = Ai.config.provider(provider)
    Ai::Llm::OpenaiCompatible.new(provider:, model:, settings:, api_key: "sk-test", http: ai_http(transport, provider:))
  end

  test "DeepSeek: JSON mode request, usage with cache and reasoning, cost from config prices at peak" do
    transport = FakeTransport.new(json_response(DEEPSEEK))
    travel_to Time.utc(2026, 11, 23, 7, 0) do # Monday 07:00 UTC — peak
      result = adapter("deepseek", transport, model: "deepseek-flash")
        .chat([ { role: "system", content: "rules" }, { role: "user", content: "text" } ], json: true, max_tokens: 4_000, temperature: 0.1)

      assert_equal({ "tokens" => [ { "surface" => "짐이" } ] }, result.json)
      assert_nil result.json_error
      assert_equal "stop", result.finish_reason
      assert_equal "deepseek", result.provider
      assert_equal 1_000, result.usage.input_tokens
      assert_equal 200, result.usage.cached_tokens
      assert_equal 1_500, result.usage.reasoning_tokens
      # 800 fresh × 0.30 + 200 cached × 0.006 + 2000 out × 1.20, per 1M
      assert_in_delta 0.0026412, result.cost_usd, 1e-7
    end

    request = transport.requests.last
    assert_equal "https://api.deepseek.com/chat/completions", request.url
    assert_equal "Bearer sk-test", request.headers["Authorization"]
    assert_equal 600, request.timeout
    body = transport.json_body
    assert_equal({ "type" => "json_object" }, body["response_format"])
    assert_equal 4_000, body["max_tokens"]
    assert_equal "deepseek-flash", body["model"]
    assert_nil body["usage"]
  end

  test "DeepSeek off-peak is half price" do
    travel_to Time.utc(2026, 11, 21, 7, 0) do # Saturday
      result = adapter("deepseek", FakeTransport.new(json_response(DEEPSEEK)), model: "deepseek-flash").chat([ { role: "user", content: "x" } ])
      assert_in_delta 0.0013206, result.cost_usd, 1e-7
    end
  end

  test "OpenRouter: asks for usage, takes the reported cost, strips code fences" do
    transport = FakeTransport.new(json_response(OPENROUTER))
    result = adapter("openrouter", transport, model: "anthropic/claude-haiku-5.5").chat([ { role: "user", content: "Describe" } ], json: true)

    assert_equal({ "text" => "a man on a beach" }, result.json)
    assert_equal 0.00131, result.cost_usd
    assert_equal({ "include" => true }, transport.json_body["usage"])
    assert_equal "https://openrouter.ai/api/v1/chat/completions", transport.requests.last.url
  end

  test "images are attached to the last user message as data URIs or URLs" do
    transport = FakeTransport.new(json_response(OPENROUTER))
    photo = StringIO.new(Episodes::PlaceholderImage.render(0.8, 1))
    adapter("openrouter", transport, model: "google/gemini-3.8-flash")
      .chat([ { role: "system", content: "rules" }, { role: "user", content: "What is here?" } ],
            images: [ photo, "https://cdn.test/place.jpg" ])

    system, user = transport.json_body["messages"]
    assert_equal "rules", system["content"]
    text, data_uri, url = user["content"]
    assert_equal({ "type" => "text", "text" => "What is here?" }, text)
    assert_match %r{\Adata:image/webp;base64,}, data_uri.dig("image_url", "url")
    assert_equal "https://cdn.test/place.jpg", url.dig("image_url", "url")
  end

  test "broken JSON is reported, not raised, so the step can retry with the error" do
    broken = DEEPSEEK.merge("choices" => [ { "finish_reason" => "length", "message" => { "content" => '{"episode": {' } } ])
    result = adapter("deepseek", FakeTransport.new(json_response(broken)), model: "deepseek-flash").chat([ { role: "user", content: "x" } ], json: true)

    assert_nil result.json
    assert result.json_error.present?
    assert_equal "length", result.finish_reason
  end

  test "a response without choices is InvalidResponse" do
    transport = FakeTransport.new(json_response({ "error" => { "message" => "model overloaded" } }))

    assert_raises(Ai::InvalidResponse) do
      adapter("deepseek", transport, model: "deepseek-flash").chat([ { role: "user", content: "x" } ])
    end
  end

  test "calls inside GenerationLog.track are added to the log" do
    transport = FakeTransport.new(json_response(OPENROUTER), json_response(OPENROUTER))
    llm = adapter("openrouter", transport, model: "anthropic/claude-haiku-5.5")

    log = GenerationLog.track(step: "tokens") do |current|
      2.times { llm.chat([ { role: "user", content: "x" } ]) }
      current
    end

    log.reload
    assert log.succeeded?
    assert_equal "openrouter", log.provider
    assert_equal "anthropic/claude-haiku-5.5", log.model
    assert_equal 6_578, log.input_tokens
    assert_equal 3_944, log.output_tokens
    assert_equal BigDecimal("0.00262"), log.cost_usd
    assert_equal 2, log.metadata["calls"]
  end
end
