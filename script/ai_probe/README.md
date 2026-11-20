# AI provider probes (wave 6 research)

Throwaway scripts to check access, latency, response format and real cost of each provider
before writing the `Ai::Llm / Image / Tts` adapters (6.1). Stdlib only, no Rails boot.

1. Keys: copy needed lines from `env.example` into `storyloop_back/.env` (gitignored).
2. `docker compose exec web ruby script/ai_probe/keys.rb` — which keys are set.
3. Probes:

| Script | What |
|---|---|
| `llm.rb deepseek\|qwen\|openrouter\|anthropic [model]` | ko-en token markup of one line, JSON mode; prints usage, cost, JSON validity |
| `image.rb "prompt" [refs...]` | Seedream image, optional reference images (local files or URLs) |
| `tts.rb Voice1,Voice2 ["text"]` | MiniMax Korean speech per voice; shows billed characters (does Korean count ×2?) |

Output: `tmp/ai_probe/` (images, audio) and `tmp/ai_probe/log.jsonl` (one line per call: seconds, usage, cost).
Prices: `prices.yml`, re-check against the consoles' billing after the first calls.
