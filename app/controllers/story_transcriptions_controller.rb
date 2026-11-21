# "Story by voice" (7.12): the browser records a short WAV (voice_input_controller.js), this turns it into text that
# lands in the idea field — the learner can fix it before creating the story. Signed-in authors only, rate limited;
# the call and its cost are in GenerationLog (step stt) with the user.
class StoryTranscriptionsController < ApplicationController
  MAX_BYTES = 3.megabytes # ~90 s of 16 kHz mono 16-bit WAV
  TYPES = %w[audio/wav audio/x-wav audio/wave].freeze

  before_action :require_author
  rate_limit to: 10, within: 1.minute, with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

  # POST { audio: <file> } → { text }
  def create
    audio = params.expect(:audio)
    return render(json: { error: "too_big" }, status: :content_too_large) if audio.size > MAX_BYTES
    return render(json: { error: "format" }, status: :unprocessable_entity) unless TYPES.include?(audio.content_type.to_s.split(";").first)

    result = GenerationLog.track(step: "stt", metadata: { "user_id" => Current.user.id, "bytes" => audio.size }) do
      Ai.stt(:stt).transcribe(audio:)
    end
    render json: { text: result.text.truncate(StoryRequest::PROMPT_LIMITS["idea"], separator: " ", omission: "") }
  rescue Ai::Error => e
    Rails.error.report(e, context: { user_id: Current.user.id })
    render json: { error: "failed" }, status: :bad_gateway
  end

  private
    def require_author
      head :forbidden if Current.user.guest? || Current.user.banned?
    end
end
