module Ai
  module Steps
    # Pipeline step "Scene" (wave M, docs/motion-research.md): tags of what each panel shows — setting, place, time,
    # weather, light, mood, shot, the character in focus and things that can move (config/schemas/scene.json). One
    # cheap LLM call per episode reads them from the image prompts and the lines. The tags do not depend on the
    # language, so a translated episode copies them with its panels (Stories::Translation). The motion player turns
    # tags into camera moves, weather and ambient sound by rules: changing those rules never needs new tags.
    #
    # Answers are normalized before the check (case, a character's name instead of its key, more than 3 elements);
    # what still fails goes back to the model. A panel left untagged after the attempts keeps its old scene; the step
    # fails only when no panel could be tagged. Callers treat the step as optional (Ai::Pipeline, Stories).
    #
    #   Ai::Steps::Scene.call(episode)              # untagged panels → {"tagged" => 10, "failed" => {}}
    #   Ai::Steps::Scene.call(episode, force: true) # every panel again
    class Scene
      include FallbackChat

      ATTEMPTS = 2
      MAX_TOKENS = 8_000
      MAX_ELEMENTS = 3

      attr_reader :episode

      def self.call(...) = new(...).call

      def initialize(episode, force: false)
        @episode = episode
        @force = force
      end

      # Panels with a picture to describe (chat has none, an illustrated section only with an image prompt).
      def panels
        @panels ||= if episode.format_chat? then []
        else
          episode.panels.includes(bubbles: :character).select { |panel| panel.image_prompt.present? && (@force || panel.scene.blank?) }
        end
      end

      def call
        return { "tagged" => 0, "failed" => {} } if panels.empty?

        GenerationLog.track(step: "scene", episode:) do |log|
          tags, problems = tag
          tags.each { |panel, scene| panel.update!(scene:) }
          summary = { "tagged" => tags.size, "failed" => problems }
          log.update!(metadata: log.metadata.merge(summary))
          raise InvalidOutput.new("no panel of episode #{episode.id} could be tagged", problems: problems.values.flatten) if tags.empty?

          summary
        end
      end

      def messages
        Prompt.messages(
          "scene", title: series.title, genre: series.genre, tone: series.tone.to_s, synopsis: episode.synopsis.to_s,
                   characters: characters.map { |c| { key: c.key, name: c.name } },
                   values: PanelScene.fields.to_h { |field| [ field, PanelScene.values(field) ] },
                   panels: panels.map { |panel| { number: panel.position + 1, image_prompt: panel.image_prompt.squish, lines: lines(panel) } }
        )
      end

      private
        def series = episode.series

        def characters = @characters ||= series.characters.order(:id).to_a

        def lines(panel)
          panel.bubbles.sort_by(&:position).map { |bubble| "#{bubble.character&.key || bubble.kind}: #{bubble.text.squish}" }
        end

        # → [{panel => scene}, {"3" => [problems]}]; panels tagged in an earlier attempt are kept.
        def tag
          messages = self.messages
          remaining = panels.index_by { |panel| panel.position + 1 }
          tags = {}
          problems = {}
          ATTEMPTS.times do
            result = chat(:scene, messages, json: true, max_tokens: MAX_TOKENS)
            answers = result.json.is_a?(Hash) ? Array(result.json["panels"]).select { |answer| answer.is_a?(Hash) } : []
            problems = {}
            remaining.each do |number, panel|
              answer = answers.find { |a| a["panel"].to_i == number }
              next problems[number.to_s] = [ "panel #{number} is missing" ] unless answer

              scene = normalize(answer)
              errors = PanelScene.errors(scene) + focus_errors(scene)
              errors.empty? ? tags[panel] = scene : problems[number.to_s] = errors
            end
            remaining = remaining.reject { |_, panel| tags.key?(panel) }
            break if remaining.empty?

            messages += [ { role: "assistant", content: result.text },
                          { role: "user", content: "Fix these panels and return {\"panels\": [...]} with them only:\n- " +
                                                   problems.map { |number, errors| "panel #{number}: #{errors.join('; ')}" }.join("\n- ") } ]
          end
          [ tags, problems ]
        end

        # Keys the schema does not know are dropped instead of costing another attempt.
        def normalize(answer)
          scene = answer.slice(*PanelScene.fields).transform_values { |value| value.is_a?(String) ? value.strip.downcase.presence : value }
          scene["focus"] = focus_key(scene["focus"])
          scene["elements"] = Array(scene["elements"]).map { |element| element.to_s.strip.downcase }.uniq.first(MAX_ELEMENTS)
          { "v" => PanelScene::VERSION }.merge(scene)
        end

        # The model often names the character instead of giving its key.
        def focus_key(value)
          return if value.nil? || %w[null none nobody].include?(value)

          characters.find { |c| c.name.casecmp?(value) }&.key || value
        end

        def focus_errors(scene)
          keys = characters.map(&:key)
          return [] if scene["focus"].nil? || keys.include?(scene["focus"])

          [ "focus: #{scene['focus'].inspect} is not a character key (#{keys.join(', ')}) or null" ]
        end
    end
  end
end
