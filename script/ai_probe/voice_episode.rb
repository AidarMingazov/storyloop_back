# Step 5 "Voice" prototype: every bubble of an episode → MiniMax with the character's voice from the series template.
#   docker compose exec web ruby script/ai_probe/voice_episode.rb tmp/ai_probe/episodes/<file>.json [series.yml]
# Narration uses NARRATOR_VOICE (default Korean_CalmLady). Output: <episode dir>/audio/pNN-bNN.mp3
require_relative "lib"

episode_path = ARGV[0] || abort("Usage: voice_episode.rb episode.json [series.yml]")
series_path = ARGV[1] || File.join(Probe::ROOT, "db/templates/ai/series/office-romance.yml")
voices = YAML.load_file(series_path).dig("series", "characters").to_h { [ _1["key"], _1["voice"] ] }
narrator = ENV.fetch("NARRATOR_VOICE", "Korean_CalmLady")
model = ENV.fetch("TTS_MODEL", "speech-2.8-turbo")
out_dir = File.join(File.dirname(episode_path), File.basename(episode_path, ".json"), "audio")
price = Probe.price("minimax", model)["per_million_chars"].to_f

total = { chars: 0, cost: 0.0, sec: 0.0, audio_ms: 0 }
JSON.parse(File.read(episode_path)).dig("episode", "panels").each_with_index do |panel, pi|
  panel["bubbles"].to_a.each_with_index do |b, bi|
    voice = b["character"] ? voices.fetch(b["character"]) : narrator
    body = { model: model, text: b["text"], stream: false, language_boost: "Korean", output_format: "hex",
             voice_setting: { voice_id: voice, speed: b["kind"] == "thought" ? 0.95 : 1.0, vol: 1, pitch: 0 },
             audio_setting: { sample_rate: 32000, bitrate: 128000, format: "mp3", channel: 1 } }
    res, sec = Probe.post_json("#{ENV.fetch('MINIMAX_BASE_URL', 'https://api.minimax.io')}/v1/t2a_v2", body,
                               { "Authorization" => "Bearer #{Probe.key!('MINIMAX_API_KEY')}" })
    abort "MiniMax #{res.dig('base_resp', 'status_code')}: #{res.dig('base_resp', 'status_msg')}" unless res.dig("base_resp", "status_code") == 0
    Probe.save(File.join(out_dir, format("p%02d-b%02d.mp3", pi + 1, bi + 1)).delete_prefix("#{Probe::OUT}/"), [ res.dig("data", "audio") ].pack("H*"))
    billed = res.dig("extra_info", "usage_characters").to_i
    total[:chars] += billed
    total[:cost] += billed * price / 1e6
    total[:sec] += sec
    total[:audio_ms] += res.dig("extra_info", "audio_length").to_i
  end
end
puts "#{out_dir.delete_prefix("#{Probe::ROOT}/")}: #{total[:chars]} billed chars, #{(total[:audio_ms] / 1000.0).round(1)}s of audio, " \
     "#{total[:sec].round(1)}s total, #{Probe.usd(total[:cost])}"
Probe.log(step: "voice_episode", provider: "minimax", model: model, seconds: total[:sec].round(2), billed_chars: total[:chars], cost_usd: total[:cost])
