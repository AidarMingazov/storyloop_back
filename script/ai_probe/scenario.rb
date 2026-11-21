# Step 1 "Scenario" prototype: series template + prompt → LLM (JSON mode) → episode JSON → checks → retry with errors.
#
#   docker compose exec web bundle exec ruby script/ai_probe/scenario.rb [series.yml] [episode_number]
#   PROVIDER=openrouter MODEL=anthropic/claude-sonnet-5.5 ... (default deepseek / deepseek-flash)
#   PANELS=10 BRIEF="Seoyeon's first day; she spills coffee on the new team leader" PREVIOUS_FILE=path
#
# Output: tmp/ai_probe/episodes/<slug>-<n>-<provider>.json (full document: language_pair + series + episode,
# no boxes/tokens yet — those are steps 3 and 4).
require_relative "lib"
require "erb"
require "json_schemer"

TEMPLATES = File.join(Probe::ROOT, "db/templates/ai")
series_path = ARGV[0] || File.join(TEMPLATES, "series/office-romance.yml")
number = (ARGV[1] || 1).to_i
provider = ENV.fetch("PROVIDER", "deepseek")
model = ENV.fetch("MODEL", provider == "deepseek" ? "deepseek-flash" : "deepseek/deepseek-v4.1-flash-1017")

doc = YAML.load_file(series_path)
series = doc.fetch("series")
vars = {
  cefr: series["cefr_level"], number: number, genre: series["genre"], title: series["title"], tone: series["tone"].to_s,
  description: series["description"], characters: series["characters"], panels: ENV.fetch("PANELS", "10"),
  previous: ENV["PREVIOUS_FILE"] && File.read(ENV["PREVIOUS_FILE"]), brief: ENV["BRIEF"]
}
system, user = ERB.new(File.read(File.join(TEMPLATES, "prompts/scenario.md.erb")), trim_mode: "-")
                  .result_with_hash(vars).split(/^---$/, 2).map(&:strip)

schema = JSONSchemer.schema(Pathname.new(File.join(Probe::ROOT, "config/schemas/episode.json")))
keys = series["characters"].map { _1["key"] }

check = lambda do |episode|
  full = { "language_pair" => doc["language_pair"],
           "series" => series.reject { |k, _| %w[characters art_style tone].include?(k) }.merge("characters" => series["characters"].map { _1.except("sheet") }),
           "episode" => episode }
  errors = schema.validate(full).map { "schema: #{_1['error']} at #{_1['data_pointer']}" }.first(10)
  episode.fetch("panels", []).each_with_index do |panel, pi|
    panel.fetch("bubbles", []).each_with_index do |b, bi|
      where = "panel #{pi + 1} bubble #{bi + 1}"
      errors << "#{where}: unknown character #{b['character'].inspect}" if b["character"] && !keys.include?(b["character"])
      errors << "#{where}: narration must have character null" if b["kind"] == "narration" && b["character"]
      len = b["text"].to_s.scan(/\p{Hangul}/).size
      errors << "#{where}: #{len} Hangul characters, keep it under 30" if len > 30
      errors << "#{where}: Latin letters or digits in Korean text" if b["text"].to_s.match?(/[A-Za-z0-9]/)
    end
  end
  [ errors, full ]
end

messages = [ { role: "system", content: system }, { role: "user", content: user } ]
total_cost = 0.0
total_sec = 0.0
result = nil
3.times do |attempt|
  text, usage, sec, cost = Probe.chat(provider, model, messages)
  total_cost += cost.to_f
  total_sec += sec
  data = Probe.parse_json(text) rescue nil
  errors, full = data ? check.call(data["episode"] || data) : [ [ "response is not valid JSON" ], nil ]
  puts "attempt #{attempt + 1}: #{sec}s, usage #{usage.compact}, cost #{Probe.usd(cost.to_f)}, #{errors.size} error(s)"
  errors.each { puts "  - #{_1}" }
  result = full
  break if errors.empty?

  messages += [ { role: "assistant", content: text },
                { role: "user", content: "Fix these problems and return the full corrected JSON:\n#{errors.join("\n")}" } ]
end

out = File.join(Probe::OUT, "episodes", "#{series['slug']}-#{number}-#{provider}-#{model.tr('/', '_')}.json")
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(result)) if result
ep = result&.dig("episode") || {}
puts "\n#{out}\n«#{ep['title']}»: #{ep['panels']&.size} panels, #{ep['panels']&.sum { _1['bubbles'].size }} bubbles, " \
     "total #{total_sec.round(1)}s, #{Probe.usd(total_cost)}"
Probe.log(step: "scenario", provider: provider, model: model, seconds: total_sec.round(2), cost_usd: total_cost, file: out.delete_prefix("#{Probe::ROOT}/"))
