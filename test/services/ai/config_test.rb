require "test_helper"
require_relative "../../test_helpers/ai_test_helper"

class Ai::ConfigTest < ActiveSupport::TestCase
  include AiTestHelper

  test "tests run every step on the fakes" do
    assert_instance_of Ai::Llm::Fake, Ai.llm(:script)
    assert_instance_of Ai::Image::Fake, Ai.image(:images)
    assert_instance_of Ai::Tts::Fake, Ai.tts(:audio)
    assert_instance_of Ai::Stt::Fake, Ai.stt(:stt)
  end

  test "live config builds the adapter of each step with its model" do
    keys = { "DEEPSEEK_API_KEY" => "d", "OPENROUTER_API_KEY" => "o", "ARK_API_KEY" => "a", "MINIMAX_API_KEY" => "m" }
    with_live_ai(keys) do
      script = Ai.llm(:script)
      assert_instance_of Ai::Llm::OpenaiCompatible, script
      assert_equal [ "deepseek", "deepseek-flash" ], [ script.provider, script.model ]

      tokens = Ai.llm(:tokens)
      assert_equal [ "openrouter", "anthropic/claude-haiku-5.5" ], [ tokens.provider, tokens.model ]
      assert_equal [ "deepseek", "deepseek-flash" ], Ai.llm(:tokens, fallback: true).then { [ _1.provider, _1.model ] }

      assert_instance_of Ai::Image::Seedream, Ai.image(:images)
      assert_equal "seedream-5-0-lite-260128", Ai.image(:photo_sheets).model
      assert_instance_of Ai::Tts::Minimax, Ai.tts(:audio)
      stt = Ai.stt(:stt)
      assert_instance_of Ai::Stt::LlmAudio, stt
      assert_equal [ "openrouter_audio", "google/gemini-3.8-flash" ], [ stt.provider, stt.model ]
      assert_equal [ "openrouter", "anthropic/claude-haiku-5.5" ], Ai.llm(:moderation).then { [ _1.provider, _1.model ] }
    end
  end

  test "AI_LIVE=1 ignores force_provider" do
    with_live_ai({ "AI_LIVE" => "1", "DEEPSEEK_API_KEY" => "d" }) do
      Ai.config = Ai::Config.new(Rails.application.config_for(:ai))
      assert_instance_of Ai::Llm::OpenaiCompatible, Ai.llm(:script)
    end
  end

  test "missing key, unknown step and wrong kind are config errors" do
    with_live_ai({ "DEEPSEEK_API_KEY" => nil }) do
      assert_raises(Ai::ConfigError) { Ai.llm(:script) }
      assert_raises(Ai::ConfigError) { Ai.llm(:nope) }
      assert_raises(Ai::ConfigError) { Ai.llm(:script, fallback: true) }
    end
    with_live_ai({ "ARK_API_KEY" => "a" }) do
      assert_raises(Ai::ConfigError) { Ai.llm(:images) } # seedream is an image provider
    end
  end
end
