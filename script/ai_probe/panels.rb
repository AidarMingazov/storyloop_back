# Step 2 "Images" prototype: panel image_prompt + series style + character sheets as references (Seedream).
#   docker compose exec web ruby script/ai_probe/panels.rb tmp/ai_probe/episodes/<file>.json [panel numbers...]
#   SERIES=db/templates/ai/series/office-romance.yml SEEDREAM_MODEL=...
# Characters are found by name in image_prompt; each one's sheet is attached as "image N".
# Output: tmp/ai_probe/episodes/<episode-file-basename>/panel-NN.jpeg
require_relative "lib"

episode_path = ARGV[0] || abort("Usage: panels.rb episode.json [1 2 3]")
series_path = ENV.fetch("SERIES", File.join(Probe::ROOT, "db/templates/ai/series/office-romance.yml"))
series = YAML.load_file(series_path).fetch("series")
sheets_dir = File.join(File.dirname(series_path), File.basename(series_path, ".yml"))
panels = JSON.parse(File.read(episode_path)).dig("episode", "panels")
numbers = ARGV[1..].to_a.map(&:to_i)
numbers = (1..panels.size).to_a if numbers.empty?
model = ENV.fetch("SEEDREAM_MODEL", "seedream-4-5-251128")
out_dir = File.join(File.dirname(episode_path), File.basename(episode_path, ".json"))
price = Probe.price("byteplus", model)

numbers.each do |n|
  panel = panels.fetch(n - 1)
  scene = panel["image_prompt"]
  cast = series["characters"].select { |c| scene.match?(/\b#{Regexp.escape(c['name'])}\b/) }
  refs = cast.map { |c| "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(File.join(sheets_dir, c['sheet'])))}" }
  legend = cast.each_with_index.map { |c, i| "Image #{i + 1} is the character sheet of #{c['name']}" }.join("; ")
  bubbles = panel["bubbles"].to_a.any?

  prompt = [
    series["style_prompt"],
    (legend.empty? ? nil : "#{legend}. Draw each of them exactly as on their sheet (face, hair, glasses, outfit), " \
                           "but in a new pose for this scene; do not copy the sheet layout or its gray background."),
    "Scene: #{scene}",
    (bubbles ? "Keep the top 25% of the frame calm and uncluttered (sky, wall or ceiling) for speech bubbles." : nil),
    "Single vertical panel, no panel borders, no text, no letters, no speech bubbles."
  ].compact.join("\n")

  body = { model: model, prompt: prompt, size: "1728x2160", response_format: "url", watermark: false }
  body[:image] = refs.one? ? refs.first : refs if refs.any?
  res, sec = Probe.post_json("#{ENV.fetch('ARK_BASE_URL', 'https://ark.ap-southeast.bytepluses.com/api/v3')}/images/generations",
                             body, { "Authorization" => "Bearer #{Probe.key!('ARK_API_KEY')}" })
  path = Probe.download(res.dig("data", 0, "url"), File.join(out_dir, format("panel-%02d.jpeg", n)))
  cost = price["image"].to_f + [ refs.size - 1, 0 ].max * price["extra_reference"].to_f
  puts "panel #{n}: #{path.delete_prefix("#{Probe::ROOT}/")} refs=#{cast.map { _1['key'] }.join(',')} #{sec}s ~#{Probe.usd(cost)}"
  Probe.log(step: "panel", provider: "byteplus", model: model, seconds: sec, refs: refs.size, cost_usd: cost,
            file: path.delete_prefix("#{Probe::ROOT}/"))
end
