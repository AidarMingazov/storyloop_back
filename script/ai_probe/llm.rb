# LLM probe: one small ko-en markup task with JSON output. Checks access, latency, usage, cost.
#
#   docker compose exec web ruby script/ai_probe/llm.rb deepseek [model]
#   docker compose exec web ruby script/ai_probe/llm.rb qwen [model]
#   docker compose exec web ruby script/ai_probe/llm.rb openrouter deepseek/deepseek-v4-flash
#   docker compose exec web ruby script/ai_probe/llm.rb anthropic [model]
#
# Optional: PROMPT_FILE=path (system prompt in line 1… user prompt after a line "---").
require_relative "lib"

PROVIDERS = {
  "deepseek" => { url: -> { "#{ENV.fetch('DEEPSEEK_BASE_URL', 'https://api.deepseek.com')}/chat/completions" },
                  key: "DEEPSEEK_API_KEY", model: "deepseek-flash" },
  "qwen" => { url: -> { "#{ENV.fetch('QWEN_BASE_URL', 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1')}/chat/completions" },
              key: "DASHSCOPE_API_KEY", model: "qwen3.5-plus" },
  "openrouter" => { url: -> { "https://openrouter.ai/api/v1/chat/completions" },
                    key: "OPENROUTER_API_KEY", model: "deepseek/deepseek-v4-flash" },
  "anthropic" => { url: -> { "https://api.anthropic.com/v1/messages" },
                   key: "ANTHROPIC_API_KEY", model: "claude-sonnet-5-5" }
}.freeze

SYSTEM = <<~TXT.freeze
  You annotate Korean comic dialogue for English-speaking A1–A2 learners.
  Return ONLY a JSON object: {"tokens": [...]}. One token per meaningful word or fixed expression, in text order.
  Token fields: surface (exactly as in the text), lemma (dictionary form, verbs/adjectives end in 다),
  pos (noun|verb|adjective|adverb|pronoun|particle|interjection|phrase|numeral|determiner),
  translation (English, in this context), romanization (Revised Romanization of the surface),
  breakdown ([{part, role: stem|ending|particle|suffix, meaning}]), politeness (casual|polite|formal, for predicates only).
TXT
USER = "Text: 안녕하세요! 저는 옆집에 사는 민호예요. 짐이 많네요, 도와드릴까요?".freeze

provider = ARGV[0] || abort("Usage: llm.rb deepseek|qwen|openrouter|anthropic [model]")
cfg = PROVIDERS.fetch(provider) { abort("Unknown provider #{provider}") }
model = ARGV[1] || cfg[:model]
key = Probe.key!(cfg[:key])

system, user = if ENV["PROMPT_FILE"]
  File.read(ENV["PROMPT_FILE"]).split(/^---$/, 2).map(&:strip)
else
  [ SYSTEM, USER ]
end

if provider == "anthropic"
  body = { model: model, max_tokens: 4000, system: system, messages: [ { role: "user", content: user } ] }
  res, sec = Probe.post_json(cfg[:url].call, body, "x-api-key" => key, "anthropic-version" => "2023-06-01")
  text = res["content"].map { _1["text"] }.join
  usage = { input: res.dig("usage", "input_tokens"), output: res.dig("usage", "output_tokens"), cached: res.dig("usage", "cache_read_input_tokens").to_i }
else
  body = { model: model, messages: [ { role: "system", content: system }, { role: "user", content: user } ],
           response_format: { type: "json_object" }, temperature: 0.3,
           max_tokens: ENV.fetch("MAX_TOKENS", "8000").to_i } # OpenRouter reserves credits for max_tokens
  body[:usage] = { include: true } if provider == "openrouter"
  res, sec = Probe.post_json(cfg[:url].call, body, "Authorization" => "Bearer #{key}")
  text = res.dig("choices", 0, "message", "content").to_s
  u = res["usage"] || {}
  usage = { input: u["prompt_tokens"], output: u["completion_tokens"],
            cached: u["prompt_cache_hit_tokens"] || u.dig("prompt_tokens_details", "cached_tokens").to_i,
            reasoning: u.dig("completion_tokens_details", "reasoning_tokens") }
  usage[:openrouter_cost] = u["cost"] if u["cost"]
end

p = Probe.price(provider, model)
cost = if usage[:openrouter_cost]
  usage[:openrouter_cost].to_f
elsif p.any?
  factor = provider == "deepseek" && !Probe.deepseek_peak? ? 0.5 : 1.0
  fresh = usage[:input].to_i - usage[:cached].to_i
  (fresh * p["input"] + usage[:cached].to_i * p.fetch("input_cached", p["input"]) + usage[:output].to_i * p["output"]) / 1e6 * factor
end

valid = begin
  JSON.parse(text.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, ""))
rescue JSON::ParserError
  nil
end

puts text
puts "\n#{provider}/#{res['model'] || model}: #{sec}s, usage #{usage.compact}, cost #{cost ? Probe.usd(cost) : 'unknown (add to prices.yml)'}, JSON #{valid ? 'ok' : 'INVALID'}"
Probe.log(step: "llm", provider: provider, model: res["model"] || model, seconds: sec, usage: usage, cost_usd: cost, json_ok: !valid.nil?)
