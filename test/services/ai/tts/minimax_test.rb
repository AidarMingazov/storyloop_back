require "test_helper"
require_relative "../../../test_helpers/ai_test_helper"

class Ai::Tts::MinimaxTest < ActiveSupport::TestCase
  include AiTestHelper

  MP3 = "ID3\x04\x00\x00fake-mp3".b

  def adapter(transport)
    Ai::Tts::Minimax.new(provider: "minimax", model: "speech-2.8-turbo", settings: Ai.config.provider("minimax"),
                         api_key: "mm-test", http: ai_http(transport, provider: "minimax"))
  end

  def spoken(characters: 38)
    json_response({ "data" => { "audio" => MP3.unpack1("H*"), "status" => 2 },
                    "extra_info" => { "audio_length" => 6_732, "usage_characters" => characters, "audio_format" => "mp3" },
                    "base_resp" => { "status_code" => 0, "status_msg" => "success" } })
  end

  test "Korean speech: request shape, hex decoding, billed characters and price" do
    transport = FakeTransport.new(spoken)
    result = adapter(transport).speak(text: "안녕하세요! 저는 옆집에 사는 민호예요.", voice: "Korean_CheerfulBoyfriend",
                                      language: "ko", speed: 0.95, emotion: "happy")

    body = transport.json_body
    assert_equal "https://api.minimax.io/v1/t2a_v2", transport.requests.last.url
    assert_equal "Korean", body["language_boost"]
    assert_equal "hex", body["output_format"]
    assert_equal({ "voice_id" => "Korean_CheerfulBoyfriend", "speed" => 0.95, "vol" => 1, "pitch" => 0, "emotion" => "happy" },
                 body["voice_setting"])

    assert_equal MP3, result.audio.read
    assert_equal "audio/mpeg", result.content_type
    assert_equal 6_732, result.audio_ms
    assert_equal 38, result.usage.characters
    assert_in_delta 38 * 60 / 1_000_000.0, result.cost_usd
  end

  test "unknown emotion and language are not sent" do
    transport = FakeTransport.new(spoken)
    adapter(transport).speak(text: "hi", voice: "English_Graceful_Lady", language: "xx", emotion: "smug")

    assert_nil transport.json_body["language_boost"]
    assert_nil transport.json_body.dig("voice_setting", "emotion")
  end

  test "errors in base_resp with HTTP 200 become typed errors" do
    { 1008 => Ai::InsufficientBalance, 1002 => Ai::RateLimited, 1004 => Ai::Unauthorized, 1026 => Ai::ContentRejected,
      2013 => Ai::ProviderError }.each do |code, klass|
      transport = FakeTransport.new(json_response({ "base_resp" => { "status_code" => code, "status_msg" => "nope" } }))
      error = assert_raises(klass) { adapter(transport).speak(text: "x", voice: "v") }
      assert_equal code, error.status
    end
  end
end
