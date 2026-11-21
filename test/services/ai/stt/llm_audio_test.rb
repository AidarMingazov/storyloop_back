require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"

class Ai::Stt::LlmAudioTest < ActiveSupport::TestCase
  include AiTestHelper

  def adapter(transport)
    settings = Ai.config.provider("openrouter_audio")
    Ai::Stt::LlmAudio.new(provider: "openrouter_audio", model: "google/gemini-3.8-flash", settings:, api_key: "sk-test",
                          http: ai_http(transport, provider: "openrouter_audio"))
  end

  test "sends the WAV as input_audio to the chat model and returns the words with the reported cost" do
    transport = FakeTransport.new(json_response({
      "model" => "google/gemini-3.8-flash",
      "choices" => [ { "message" => { "content" => " Кот-детектив ищет торт. \n" } } ],
      "usage" => { "prompt_tokens" => 420, "completion_tokens" => 12, "cost" => 0.00041 }
    }))

    result = adapter(transport).transcribe(audio: file_fixture("line.wav"))

    assert_equal "Кот-детектив ищет торт.", result.text
    assert_in_delta 0.00041, result.cost_usd, 1e-9
    assert_equal [ 420, "openrouter_audio" ], [ result.usage.input_tokens, result.provider ]
    body = transport.json_body
    assert_equal "google/gemini-3.8-flash", body["model"]
    parts = body["messages"].sole["content"]
    assert_match(/word for word/, parts.first["text"])
    assert_equal "wav", parts.last.dig("input_audio", "format")
    assert_equal file_fixture("line.wav").binread, Base64.strict_decode64(parts.last.dig("input_audio", "data"))
    assert_equal({ "include" => true }, body["usage"])
    assert_equal "Bearer sk-test", transport.requests.sole.headers["Authorization"]
  end

  test "an answer without text is an invalid response; other audio types are refused" do
    transport = FakeTransport.new(json_response({ "choices" => [] }))
    assert_raises(Ai::InvalidResponse) { adapter(transport).transcribe(audio: file_fixture("line.wav")) }

    assert_raises(ArgumentError) { adapter(FakeTransport.new).transcribe(audio: StringIO.new("webm")) }
  end

  test "the provider uses the openrouter key" do
    with_live_ai("OPENROUTER_API_KEY" => "sk-or") do
      assert_equal "sk-or", Ai.config.api_key("openrouter_audio") if Rails.application.credentials.dig(:ai, :openrouter_api_key).blank?
      assert_kind_of Ai::Stt::LlmAudio, Ai.stt(:stt)
    end
  end
end
