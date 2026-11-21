require "test_helper"
require_relative "../test_helpers/ai_test_helper"

class GenerationLogTest < ActiveSupport::TestCase
  include AiTestHelper

  test "track sums every AI call of the block and marks success" do
    Ai::Llm::Fake.respond_with("x" * 400, "y" * 40)

    log = GenerationLog.track(step: "script", metadata: { "attempt" => 1 }) do |current|
      Ai.llm(:script).chat([ { role: "user", content: "a" * 80 } ])
      Ai.llm(:script).chat([ { role: "user", content: "b" * 40 } ])
      Ai.tts(:audio).speak(text: "안녕", voice: "v")
      current
    end

    log.reload
    assert log.succeeded?
    assert_equal "script", log.step
    assert_equal 30, log.input_tokens
    assert_equal 110, log.output_tokens
    assert_equal 2, log.characters
    assert_equal 3, log.metadata["calls"]
    assert_equal 1, log.metadata["attempt"]
    assert_not_nil log.duration_ms
  end

  test "an error marks the log failed with the message and is re-raised" do
    Ai::Image::Fake.respond_with(Ai::ContentRejected.new("seedream: rejected by the safety filter"))

    assert_raises(Ai::ContentRejected) do
      GenerationLog.track(step: "images") { Ai.image(:images).generate(prompt: "x") }
    end

    log = GenerationLog.order(:id).last
    assert log.failed?
    assert_equal "Ai::ContentRejected: seedream: rejected by the safety filter", log.error
    assert_nil Ai.current_log
  end

  test "calls outside track are not logged; nested track restores the outer log" do
    assert_no_difference("GenerationLog.count") { Ai.llm(:script).chat([ { role: "user", content: "x" } ]) }

    outer = GenerationLog.track(step: "images") do |log|
      GenerationLog.track(step: "sheets") { Ai.image(:sheets).generate(prompt: "sheet") }
      Ai.image(:images).generate(prompt: "panel")
      log
    end

    assert_equal 1, outer.reload.images
    assert_equal 1, GenerationLog.find_by!(step: "sheets").images
  end

  test "unknown step is invalid" do
    assert_raises(ActiveRecord::RecordInvalid) { GenerationLog.track(step: "dance") { } }
  end
end
