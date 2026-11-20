# MiniMax TTS probe: Korean line(s) with one or more system voices.
#
#   docker compose exec web ruby script/ai_probe/tts.rb Korean_CheerfulBoyfriend "짐이 많네요, 도와드릴까요?"
#   docker compose exec web ruby script/ai_probe/tts.rb Korean_CalmLady,Korean_SweetGirl,Korean_ReliableYouth
#
# ENV: MINIMAX_API_KEY (required), TTS_MODEL (speech-2.8-turbo | speech-2.8-hd), EMOTION, SPEED, MINIMAX_BASE_URL.
# Voices list: https://platform.minimax.io/docs/faq/system-voice-id (Korean_* ids).
require_relative "lib"

voices = (ARGV[0] || abort("Usage: tts.rb Voice_Id[,Voice_Id2] [\"text\"]")).split(",")
text = ARGV[1] || "안녕하세요! 저는 옆집에 사는 민호예요. 짐이 많네요, 도와드릴까요?"
model = ENV.fetch("TTS_MODEL", "speech-2.8-turbo")
base = ENV.fetch("MINIMAX_BASE_URL", "https://api.minimax.io")
price = Probe.price("minimax", model)["per_million_chars"]

voices.each do |voice|
  voice_setting = { voice_id: voice, speed: ENV.fetch("SPEED", "1").to_f, vol: 1, pitch: 0 }
  voice_setting[:emotion] = ENV["EMOTION"] if ENV["EMOTION"]
  body = { model: model, text: text, stream: false, language_boost: "Korean", output_format: "hex",
           voice_setting: voice_setting, audio_setting: { sample_rate: 32000, bitrate: 128000, format: "mp3", channel: 1 } }
  res, sec = Probe.post_json("#{base}/v1/t2a_v2", body, "Authorization" => "Bearer #{Probe.key!('MINIMAX_API_KEY')}")
  status = res.dig("base_resp", "status_code")
  abort "MiniMax error #{status}: #{res.dig('base_resp', 'status_msg')}" unless status == 0

  info = res["extra_info"] || {}
  path = Probe.save("audio/#{voice}-#{Probe.stamp}.mp3", [ res.dig("data", "audio") ].pack("H*"))
  billed = info["usage_characters"].to_i
  cost = price ? billed * price / 1e6 : nil
  puts "#{path}\n  #{voice}: #{sec}s, audio #{info['audio_length']}ms, text #{text.length} chars → billed #{billed} " \
       "(×#{(billed.to_f / text.length).round(2)}), cost #{cost ? Probe.usd(cost) : '?'}"
  Probe.log(step: "tts", provider: "minimax", model: model, voice: voice, seconds: sec, chars: text.length,
            billed_chars: billed, audio_ms: info["audio_length"], cost_usd: cost, file: path.delete_prefix("#{Probe::ROOT}/"))
end
