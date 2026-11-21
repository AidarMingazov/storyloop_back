require "erb"

module Ai
  # Prompt templates in db/templates/ai/prompts/<name>.md.erb: "<system prompt>\n---\n<user prompt>".
  module Prompt
    DIR = Rails.root.join("db/templates/ai/prompts")

    module_function

    def render(name, **vars)
      ERB.new(DIR.join("#{name}.md.erb").read, trim_mode: "-").result_with_hash(vars)
    end

    def messages(name, **vars)
      system, user = render(name, **vars).split(/^---$/, 2).map(&:strip)
      [ { role: "system", content: system }, { role: "user", content: user } ].select { |m| m[:content].present? }
    end
  end
end
