module Ai
  module Llm
    # json: parsed JSON when the call asked for json: true and the text parsed (else nil, see json_error).
    # finish_reason "length" means the answer was cut by max_tokens.
    Result = Data.define(:text, :json, :json_error, :finish_reason, :usage, :cost_usd, :duration_ms, :provider, :model)

    module_function

    # Text of a JSON answer → [object, nil] or [nil, error message]. Tolerates ```json fences.
    def parse_json(text)
      [ JSON.parse(text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")), nil ]
    rescue JSON::ParserError => e
      [ nil, e.message[0, 300] ]
    end
  end
end
