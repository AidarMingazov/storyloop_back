require "test_helper"

class StoryTranscriptionsControllerTest < ActionDispatch::IntegrationTest
  def wav(type: "audio/wav") = fixture_file_upload("line.wav", type)

  test "a signed-in author gets the text of the recording; the call is logged with the user" do
    sign_in_as users(:one)
    Ai::Stt::Fake.respond_with("A cat detective looks for a lost cake at a wedding")

    post story_transcription_path, params: { audio: wav }

    assert_response :success
    assert_equal "A cat detective looks for a lost cake at a wedding", response.parsed_body["text"]
    log = GenerationLog.where(step: "stt").sole
    assert_equal users(:one).id, log.metadata["user_id"]
  ensure
    Ai::Stt::Fake.reset!
  end

  test "visitors, guests and other formats are refused; a provider error is a 502" do
    post story_transcription_path, params: { audio: wav }
    assert_response :redirect # sign in first

    sign_in_as users(:guest)
    post story_transcription_path, params: { audio: wav }
    assert_response :forbidden

    sign_in_as users(:one)
    post story_transcription_path, params: { audio: wav(type: "audio/webm") }
    assert_response :unprocessable_entity

    Ai::Stt::Fake.respond_with(Ai::ProviderError.new("down", provider: "openrouter_audio"))
    post story_transcription_path, params: { audio: wav }
    assert_response :bad_gateway
    assert_equal "failed", response.parsed_body["error"]
  ensure
    Ai::Stt::Fake.reset!
  end
end
