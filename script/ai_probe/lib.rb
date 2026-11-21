# Shared helpers for AI provider probes. Stdlib only: no gems, no Rails boot.
#
# Keys come from ENV or from storyloop_back/.env (gitignored). Values are never printed.
# Every call is logged to tmp/ai_probe/log.jsonl; files (images, audio) go to tmp/ai_probe/.
require "net/http"
require "json"
require "uri"
require "yaml"
require "time"
require "fileutils"
require "base64"

module Probe
  ROOT = File.expand_path("../..", __dir__)
  OUT = File.join(ROOT, "tmp/ai_probe")
  PRICES = YAML.load_file(File.join(__dir__, "prices.yml"))

  module_function

  def load_env!
    path = File.join(ROOT, ".env")
    return unless File.exist?(path)

    File.foreach(path) do |line|
      next if line.strip.empty? || line.lstrip.start_with?("#")
      key, value = line.split("=", 2)
      next unless value
      ENV[key.strip] ||= value.strip.delete_prefix('"').delete_suffix('"')
    end
  end

  def key!(name)
    ENV[name].to_s.empty? ? abort("#{name} is not set (put it in storyloop_back/.env)") : ENV[name]
  end

  def keys_status(names)
    names.map { |n| "#{n}: #{ENV[n].to_s.empty? ? '—' : 'set'}" }.join(", ")
  end

  # POST JSON, return [parsed_body, seconds]. Raises with the provider's error body on non-2xx.
  # headers is positional on purpose: with a keyword arg Ruby would treat "Authorization" => ... as keywords.
  def post_json(url, body, headers = {}, timeout = 300)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" }.merge(headers))
    req.body = JSON.generate(body)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: timeout, open_timeout: 30) do |http|
      http.request(req)
    end
    seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
    parsed = JSON.parse(res.body) rescue { "raw" => res.body.to_s[0, 2000] }
    raise "HTTP #{res.code} from #{uri.host}: #{JSON.generate(parsed)[0, 1500]}" unless res.is_a?(Net::HTTPSuccess)

    [ parsed, seconds ]
  end

  OPENAI_COMPATIBLE = {
    "deepseek" => [ "https://api.deepseek.com/chat/completions", "DEEPSEEK_API_KEY" ],
    "openrouter" => [ "https://openrouter.ai/api/v1/chat/completions", "OPENROUTER_API_KEY" ]
  }.freeze

  # Chat call with JSON mode. messages: [{role:, content:}]. Returns [text, usage_hash, seconds, cost_usd].
  def chat(provider, model, messages, max_tokens: 16_000, temperature: 0.7)
    url, key_name = OPENAI_COMPATIBLE.fetch(provider)
    body = { model: model, messages: messages, response_format: { type: "json_object" },
             temperature: temperature, max_tokens: max_tokens }
    body[:usage] = { include: true } if provider == "openrouter"
    res, sec = post_json(url, body, { "Authorization" => "Bearer #{key!(key_name)}" }, 600)
    u = res["usage"] || {}
    usage = { input: u["prompt_tokens"].to_i, output: u["completion_tokens"].to_i,
              cached: (u["prompt_cache_hit_tokens"] || u.dig("prompt_tokens_details", "cached_tokens")).to_i,
              reasoning: u.dig("completion_tokens_details", "reasoning_tokens") }
    cost = if u["cost"]
      u["cost"].to_f
    elsif (p = price(provider, model)).any?
      factor = provider == "deepseek" && !deepseek_peak? ? 0.5 : 1.0
      ((usage[:input] - usage[:cached]) * p["input"] + usage[:cached] * p.fetch("input_cached", p["input"]) +
        usage[:output] * p["output"]) / 1e6 * factor
    end
    [ res.dig("choices", 0, "message", "content").to_s, usage, sec, cost ]
  end

  def parse_json(text)
    JSON.parse(text.sub(/\A\s*```(?:json)?\s*/, "").sub(/```\s*\z/, ""))
  end

  def download(url, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, Net::HTTP.get(URI(url)))
    path
  end

  def save(name, bytes)
    path = File.join(OUT, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, bytes)
    path
  end

  def stamp
    Time.now.utc.strftime("%Y%m%d-%H%M%S")
  end

  # entry: { step:, provider:, model:, seconds:, usage:, cost_usd:, ... }
  def log(entry)
    FileUtils.mkdir_p(OUT)
    File.open(File.join(OUT, "log.jsonl"), "a") { |f| f.puts JSON.generate({ at: Time.now.utc.iso8601 }.merge(entry)) }
    entry
  end

  def price(provider, model)
    PRICES.dig(provider, model) || {}
  end

  # DeepSeek: off-peak is half price outside 01–04 and 06–10 UTC on weekdays.
  def deepseek_peak?(time = Time.now.utc)
    !time.saturday? && !time.sunday? && ((1...4).cover?(time.hour) || (6...10).cover?(time.hour))
  end

  def usd(value)
    format("$%.5f", value)
  end
end

Probe.load_env!
