# Step 4 "Word markup" prototype + 6.10 mini-comparison: same bubbles → several models → automatic checks.
#   docker compose exec web ruby script/ai_probe/markup.rb episode1.json [episode2.json ...]
#   LIMIT=20 MODELS="deepseek:deepseek-flash,openrouter:anthropic/claude-sonnet-5.5,openrouter:anthropic/claude-haiku-5.5"
# Checks per bubble: surfaces found in order (as script/validate_episode.rb), punctuation in surface, uncovered Hangul
# words, verb/adjective lemma ending in 다, missing romanization/translation. Output: tmp/ai_probe/markup/<model>.json
require_relative "lib"
require "erb"

files = ARGV.empty? ? abort("Usage: markup.rb episode.json ...") : ARGV
limit = ENV.fetch("LIMIT", "20").to_i
models = ENV.fetch("MODELS", "deepseek:deepseek-flash,openrouter:anthropic/claude-sonnet-5.5,openrouter:anthropic/claude-haiku-5.5").split(",")

bubbles = []
targets = []
cefr = nil
files.each_with_index do |f, fi|
  doc = JSON.parse(File.read(f))
  cefr ||= doc.dig("episode", "cefr_level")
  targets += doc.dig("episode", "target_words").to_a
  names = doc.dig("series", "characters").to_h { [ _1["key"], _1["name"] ] }
  doc.dig("episode", "panels").each_with_index do |p, pi|
    p["bubbles"].to_a.each_with_index do |b, bi|
      bubbles << { id: "e#{fi + 1}p#{pi + 1}b#{bi + 1}", text: b["text"], translation: b["translation"],
                   kind: b["kind"], speaker: names[b["character"]] || "Narrator" }
    end
  end
end
# take an even spread across all files
bubbles = bubbles.each_slice([ (bubbles.size / limit.to_f).ceil, 1 ].max).map(&:first).first(limit)

system, user = ERB.new(File.read(File.join(Probe::ROOT, "db/templates/ai/prompts/markup.md.erb")), trim_mode: "-")
                  .result_with_hash(cefr: cefr, target_words: targets.uniq, bubbles: bubbles).split(/^---$/, 2).map(&:strip)

def check(text, tokens)
  errors = []
  cursor = 0
  tokens.each do |t|
    s = t["surface"].to_s
    errors << "punctuation in #{s.inspect}" if s.match?(/[[:punct:]…]/)
    start = text.index(s, cursor)
    if start.nil? then errors << "#{s.inspect} not found in order"; next end
    cursor = start + s.length
    if %w[verb adjective].include?(t["pos"]) && !t["lemma"].to_s.end_with?("다")
      errors << "lemma #{t['lemma'].inspect} of #{t['pos']} does not end in 다"
    end
    errors << "no romanization for #{s.inspect}" if t["romanization"].to_s.empty?
  end
  covered = tokens.flat_map { _1["surface"].to_s.split }
  missing = text.scan(/\p{Hangul}+/) - covered.flat_map { _1.scan(/\p{Hangul}+/) }
  errors << "uncovered: #{missing.join(' ')}" if missing.any?
  errors
end

models.each do |spec|
  provider, model = spec.split(":", 2)
  begin
    text, usage, sec, cost = Probe.chat(provider, model, [ { role: "system", content: system }, { role: "user", content: user } ],
                                        max_tokens: 24_000, temperature: 0.1)
    data = Probe.parse_json(text)
    by_id = data["bubbles"].to_a.to_h { [ _1["id"], _1["tokens"].to_a ] }
    report = bubbles.map { |b| { id: b[:id], text: b[:text], errors: check(b[:text], by_id[b[:id]].to_a), tokens: by_id[b[:id]].to_a } }
    bad = report.count { _1[:errors].any? }
    out = File.join(Probe::OUT, "markup", "#{model.tr('/', '_')}.json")
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, JSON.pretty_generate(report))
    puts "#{spec}: #{sec}s, out #{usage[:output]} tok (reasoning #{usage[:reasoning].inspect}), #{Probe.usd(cost.to_f)}, " \
         "#{bubbles.size - bad}/#{bubbles.size} bubbles clean"
    report.select { _1[:errors].any? }.first(8).each { puts "  #{_1[:id]} #{_1[:text]} → #{_1[:errors].join('; ')}" }
    Probe.log(step: "markup", provider: provider, model: model, seconds: sec, usage: usage, cost_usd: cost, clean: bubbles.size - bad, total: bubbles.size)
  rescue => e
    puts "#{spec}: ERROR #{e.message[0, 300]}"
  end
end
