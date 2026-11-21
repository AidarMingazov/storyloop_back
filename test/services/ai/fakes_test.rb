require "test_helper"
require_relative "../../test_helpers/ai_test_helper"

class Ai::FakesTest < ActiveSupport::TestCase
  include AiTestHelper

  test "LLM fake answers scripted items in order, then defaults, and keeps calls" do
    Ai::Llm::Fake.respond_with({ "episode" => { "number" => 1 } }, "plain")
    llm = Ai.llm(:script)

    assert_equal({ "episode" => { "number" => 1 } }, llm.chat([ { role: "user", content: "write" } ], json: true).json)
    assert_equal "plain", llm.chat([ { role: "user", content: "x" } ]).text
    assert_equal({}, llm.chat([ { role: "user", content: "x" } ], json: true).json)
    assert_equal 3, Ai::Llm::Fake.calls.size
    assert_equal "script", Ai::Llm::Fake.calls.first[:step]
  end

  test "fakes raise scripted errors" do
    Ai::Llm::Fake.respond_with(Ai::RateLimited.new("busy"))
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("no"))

    assert_raises(Ai::RateLimited) { Ai.llm(:tokens).chat([ { role: "user", content: "x" } ]) }
    assert_raises(Ai::ContentRejected) { Ai.image(:images).generate(prompt: "x") }
  end

  test "image fake draws a placeholder with the requested aspect" do
    result = Ai.image(:images).generate(prompt: "panel", references: [ "a", "b" ], size: "1000x2000")
    image = Vips::Image.new_from_buffer(result.image.io.read, "")

    assert_equal "image/webp", result.image.content_type
    assert_in_delta 0.5, image.width.to_f / image.height, 0.01
    assert_equal({ step: "images", prompt: "panel", references: 2, size: "1000x2000" }, Ai::Image::Fake.calls.last)
  end

  test "tts fake returns a playable silent wav" do
    result = Ai.tts(:audio).speak(text: "안녕하세요", voice: "Korean_SweetGirl", language: "ko")
    bytes = result.audio.read

    assert_equal "RIFF", bytes[0, 4]
    assert_equal "WAVE", bytes[8, 4]
    assert_equal 500, result.audio_ms
    assert_equal 5, result.usage.characters
  end

  test "stt fake returns scripted text" do
    Ai::Stt::Fake.respond_with("서울에서 길을 잃은 두 친구")

    assert_equal "서울에서 길을 잃은 두 친구", Ai.stt(:stt).transcribe(audio: StringIO.new("x"), language: "ko").text
  end
end
