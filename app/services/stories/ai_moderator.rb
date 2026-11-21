module Stories
  # AI text classifier for user stories (7.6, STORY_MODERATOR=pipeline): the brief before generation and the finished
  # story before it goes out (GenerateStoryJob). A cheap model with a JSON verdict (config/ai.yml step "moderation");
  # the call and its cost go to GenerationLog, with the episode when there is one. A model that keeps answering
  # nonsense raises (the story fails without counting) — nothing unchecked gets published.
  #
  #   Stories::AiModerator.new.check("Masha bakes a cake")  # => Verdict(ok: true)
  class AiModerator
    include Ai::Steps::FallbackChat

    ATTEMPTS = 2
    MAX_TEXT = 12_000 # characters; a story is ~2–4K

    def check(text, episode: nil)
      text = text.to_s.strip
      return Verdict.ok if text.blank?

      GenerationLog.track(step: "moderation", episode:, metadata: { "stage" => stage(episode), "length" => text.length }) do |log|
        verdict = classify(text, stage(episode))
        log.update!(metadata: log.metadata.merge("allowed" => verdict.ok?, "category" => verdict.category, "reason" => verdict.reason))
        verdict
      end
    end

    private
      def stage(episode) = episode ? "story" : "brief"

      def classify(text, stage)
        messages = Ai::Prompt.messages("moderation", text: text.first(MAX_TEXT), stage:)
        ATTEMPTS.times do
          json = chat(:moderation, messages, json: true, max_tokens: 400, temperature: 0).json
          next unless json.is_a?(Hash) && [ true, false ].include?(json["allowed"])

          return Verdict.ok if json["allowed"]

          category = REJECTIONS.include?(json["category"]) ? json["category"] : "other"
          return Verdict.rejected(json["reason"].to_s.truncate(300).presence || category, category:)
        end
        raise Ai::InvalidOutput.new("moderation: no verdict", problems: [ "the answer had no \"allowed\": true|false" ])
      end
  end
end
