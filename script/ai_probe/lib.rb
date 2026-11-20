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
  def post_json(url, body, headers = {}, timeout: 300)
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

  def download(url, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, Net::HTTP.get(URI(url)))
    path
  end

  def save(name, bytes)
    FileUtils.mkdir_p(OUT)
    path = File.join(OUT, name)
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
