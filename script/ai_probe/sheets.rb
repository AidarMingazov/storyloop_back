# Character reference sheets for a series template (Seedream). One image per character.
#   docker compose exec web ruby script/ai_probe/sheets.rb [series.yml] [character_key ...]
# Output: db/templates/ai/series/<slug>/characters/<key>.jpeg (the `sheet` path in the template).
require_relative "lib"

templates = File.join(Probe::ROOT, "db/templates/ai")
series_path = ARGV[0] || File.join(templates, "series/office-romance.yml")
series = YAML.load_file(series_path).fetch("series")
only = ARGV[1..].to_a
model = ENV.fetch("SEEDREAM_MODEL", "seedream-4-5-251128")
dir = File.join(File.dirname(series_path), File.basename(series_path, ".yml"))

series["characters"].each do |c|
  next if only.any? && !only.include?(c["key"])

  prompt = [
    series["art_style"] || series["style_prompt"],
    "Character model sheet of ONE character, #{c['name']}: #{c['appearance_prompt']}",
    "Flat plain light-gray background everywhere, no scenery, no sparkles. Four views side by side: " \
    "full body front view, full body three-quarter view, head-and-shoulders close-up with a neutral face, " \
    "head-and-shoulders close-up smiling.",
    "Identical person in every view: same face, hairstyle, glasses and accessories, same outfit; even studio lighting, " \
    "no props, no other people.",
    "No text, labels, names, numbers or color swatches."
  ].join("\n")
  res, sec = Probe.post_json("#{ENV.fetch('ARK_BASE_URL', 'https://ark.ap-southeast.bytepluses.com/api/v3')}/images/generations",
                             { model: model, prompt: prompt, size: "2560x1440", response_format: "url", watermark: false },
                             { "Authorization" => "Bearer #{Probe.key!('ARK_API_KEY')}" })
  path = Probe.download(res.dig("data", 0, "url"), File.join(dir, c.fetch("sheet")))
  cost = Probe.price("byteplus", model)["image"]
  puts "#{c['key']}: #{path.delete_prefix("#{Probe::ROOT}/")} (#{sec}s, ~#{Probe.usd(cost.to_f)} or free quota)"
  Probe.log(step: "sheet", provider: "byteplus", model: model, seconds: sec, cost_usd: cost, file: path.delete_prefix("#{Probe::ROOT}/"))
end
