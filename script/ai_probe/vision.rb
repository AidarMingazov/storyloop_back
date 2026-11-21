# 7.11 research: describe user photos for the scenario writer (people/animals → characters, places → backgrounds).
#   docker compose exec web bundle exec ruby script/ai_probe/vision.rb photo1.jpg [photo2.jpg ...]
#   MODELS="anthropic/claude-sonnet-5.5,qwen/qwen3.8-flash" (OpenRouter ids; "deepseek:deepseek-flash" = direct)
# Photos live in tmp/ai_probe/photos/ (gitignored) and are deleted after the test. Images are downscaled to 1024px.
# Output: tmp/ai_probe/vision/<model>.json + timing/cost lines.
require_relative "lib"

photos = ARGV.empty? ? abort("Usage: vision.rb photo.jpg ...") : ARGV
models = ENV.fetch("MODELS", "anthropic/claude-sonnet-5.5,anthropic/claude-haiku-5.5,qwen/qwen3.8-flash,google/gemini-3.8-flash").split(",")

PROMPT = <<~TXT.freeze
  You prepare photos for a comic-strip writer. The photos were uploaded by the user to turn into a short Korean-learning
  webtoon. Describe ONLY what is visible; never guess identities, names, ethnicity, health or other sensitive traits.
  Return ONLY JSON:
  {"photos": [{"index": 1, "scene": "one sentence", "place": {"kind": "...", "details": "...", "time_of_day": "...", "usable_as_background": true},
   "subjects": [{"ref": "p1_a", "type": "person|animal", "approx_age": "child|teen|20s|30s|40s|50s+|unknown",
     "look": "hair, face shape, glasses, build — for a cartoon character sheet", "outfit": "...", "expression": "...", "action": "..."}],
   "objects": ["notable props"], "mood": "..."}],
   "same_subject_across_photos": [["p1_a", "p2_b"]],
   "story_hooks": ["3 short ideas for a light slice-of-life story that connects these photos"]}
TXT

def data_uri(path)
  small = File.join(Probe::OUT, "photos_small", File.basename(path, ".*") + ".jpg")
  FileUtils.mkdir_p(File.dirname(small))
  require "vips" # ruby-vips from the app bundle: run with `bundle exec`
  Vips::Image.thumbnail(path, 1024, height: 1024).autorot.jpegsave(small, Q: 85, strip: true) unless File.exist?(small)
  "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(small))}"
end

content = [ { type: "text", text: PROMPT } ] + photos.map { { type: "image_url", image_url: { url: data_uri(_1) } } }
models.each do |m|
  provider, model = m.start_with?("deepseek:") ? [ "deepseek", m.delete_prefix("deepseek:") ] : [ "openrouter", m ]
  begin
    text, usage, sec, cost = Probe.chat(provider, model, [ { role: "user", content: content } ], max_tokens: 4000, temperature: 0.2)
    json = Probe.parse_json(text) rescue nil
    out = File.join(Probe::OUT, "vision", "#{model.tr('/', '_')}.json")
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, json ? JSON.pretty_generate(json) : text)
    puts "#{m}: #{sec}s, in #{usage[:input]} / out #{usage[:output]} tok, #{Probe.usd(cost.to_f)}, JSON #{json ? 'ok' : 'INVALID'} → #{out.delete_prefix("#{Probe::ROOT}/")}"
    Probe.log(step: "vision", provider: provider, model: model, seconds: sec, usage: usage, cost_usd: cost, photos: photos.size)
  rescue => e
    puts "#{m}: ERROR #{e.message[0, 300]}"
  end
end
