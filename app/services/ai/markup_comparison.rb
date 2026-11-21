module Ai
  # Admin "Сравнение разметки" (6.10): the first BUBBLES bubbles of an episode marked up by several models with the
  # production prompt and Ai::TokenCheck. Nothing is written to tokens: each model's answer, problems, time and cost
  # stay in its GenerationLog (step "markup_comparison", metadata comparison = id).
  #
  #   id = Ai::MarkupComparison.start(episode, ["openrouter:anthropic/claude-haiku-5.5", "deepseek:deepseek-flash"])
  #   Ai::MarkupComparison.logs(id)
  module MarkupComparison
    BUBBLES = 20
    FIELDS = %w[surface lemma pos translation romanization politeness note].freeze

    module_function

    def start(episode, models)
      id = SecureRandom.uuid
      CompareMarkupJob.perform_later(episode, models, id)
      id
    end

    def logs(id) = GenerationLog.where(step: "markup_comparison").where("metadata->>'comparison' = ?", id).order(:id)

    # [[id, [logs]], …] newest first
    def recent(limit = 10)
      GenerationLog.where(step: "markup_comparison").order(id: :desc).limit(limit * 6).to_a
                   .group_by { |log| log.metadata["comparison"] }.first(limit)
    end

    def bubbles(episode) = episode.panels.includes(bubbles: :character).flat_map(&:bubbles).first(BUBBLES)

    def bubble_id(bubble) = "p#{bubble.panel.position + 1}b#{bubble.position + 1}"

    # One thread per model; a failing model is recorded in its log and does not stop the others.
    def run(id, episode, models)
      models.map { |spec| Thread.new { Rails.application.executor.wrap { compare(id, episode, spec) } } }.each(&:join)
    end

    def compare(id, episode, spec)
      provider, model = spec.split(":", 2)
      list = bubbles(episode)
      step = Steps::Tokens.new(episode, bubbles: list)
      pair = episode.series.language_pair
      target = Language[pair.target_lang]
      native = Language[pair.native_lang]
      metadata = { "comparison" => id, "episode_id" => episode.id, "label" => spec }
      GenerationLog.track(step: "markup_comparison", metadata:) do |log|
        result = Ai.llm_for(provider, model).chat(step.messages(list), json: true, max_tokens: Steps::Tokens::MAX_TOKENS, temperature: 0.1)
        answer = result.json.is_a?(Hash) ? Array(result.json["bubbles"]).select { |b| b.is_a?(Hash) }.to_h { |b| [ b["id"].to_s, b["tokens"] ] } : {}
        report = list.to_h do |bubble|
          tokens = Array(answer[bubble_id(bubble)]).select { |t| t.is_a?(Hash) }
          problems = TokenCheck.new(bubble.text, tokens, target:, native:).problems
          [ bubble_id(bubble), { "tokens" => tokens.map { |t| t.slice(*FIELDS).compact_blank }, "problems" => problems } ]
        end
        log.update!(metadata: log.metadata.merge("bubbles" => report, "clean" => report.count { |_, r| r["problems"].empty? },
                                                 "cut_off" => result.finish_reason == "length", "json_error" => result.json_error))
      end
    rescue Ai::Error => e
      Rails.logger.warn("[ai] markup comparison #{spec}: #{e.message.truncate(200)}") # the log has the error
    end
  end
end
