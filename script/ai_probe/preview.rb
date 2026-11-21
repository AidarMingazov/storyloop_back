# Builds a throwaway HTML preview of a generated episode: panels (if rendered), bubbles, translations, audio.
#   docker compose exec web ruby script/ai_probe/preview.rb tmp/ai_probe/episodes/<file>.json
# Output: <episode dir>/index.html (open from the host: storyloop_back/tmp/ai_probe/episodes/<name>/index.html)
require_relative "lib"
require "erb"

path = ARGV[0] || abort("Usage: preview.rb episode.json")
doc = JSON.parse(File.read(path))
ep = doc["episode"]
names = doc.dig("series", "characters").to_h { [ _1["key"], _1["name"] ] }
dir = File.join(File.dirname(path), File.basename(path, ".json"))
h = ->(s) { ERB::Util.html_escape(s.to_s) }

panels = ep["panels"].each_with_index.map do |p, pi|
  img = format("panel-%02d.jpeg", pi + 1)
  pic = File.exist?(File.join(dir, img)) ? %(<img src="#{img}">) : %(<div class="ph">#{h[p['image_prompt']]}</div>)
  bubbles = p["bubbles"].to_a.each_with_index.map do |b, bi|
    audio = format("audio/p%02d-b%02d.mp3", pi + 1, bi + 1)
    who = b["character"] ? names[b["character"]] : "Narration"
    play = File.exist?(File.join(dir, audio)) ? %(<audio controls preload="none" src="#{audio}"></audio>) : ""
    %(<div class="b #{b['kind']}"><span class="who">#{h[who]} · #{b['kind']}</span><p class="ko">#{h[b['text']]}</p>) +
      %(<p class="en">#{h[b['translation']]}</p>#{play}</div>)
  end.join
  %(<section><div class="n">#{pi + 1}</div>#{pic}#{bubbles}</section>)
end.join

File.write(File.join(dir, "index.html"), <<~HTML)
  <!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>#{h[ep['title']]}</title><style>
  body{margin:0;background:#f4f1ea;font:16px/1.45 system-ui,sans-serif;color:#222}
  main{max-width:480px;margin:0 auto;padding:16px}
  h1{font-size:20px} .meta{color:#666;font-size:14px}
  section{background:#fff;border-radius:12px;margin:16px 0;overflow:hidden;position:relative;box-shadow:0 1px 3px #0002}
  img{width:100%;display:block} .ph{aspect-ratio:4/5;background:#ddd;color:#555;padding:16px;font-size:13px;box-sizing:border-box}
  .n{position:absolute;top:8px;left:8px;background:#000a;color:#fff;border-radius:8px;padding:0 8px;font-size:13px}
  .b{padding:10px 14px;border-top:1px solid #eee} .who{font-size:12px;color:#888}
  .ko{font-size:19px;margin:2px 0} .en{margin:0;color:#555;font-size:14px} .thought .ko{font-style:italic}
  .narration{background:#faf7ef} audio{width:100%;height:32px;margin-top:6px}
  </style></head><body><main>
  <h1>#{h[ep['title']]}</h1>
  <p class="meta">#{h[doc.dig('series', 'title')]} · #{h[ep['cefr_level']]} · #{ep['panels'].size} panels</p>
  <p class="meta">#{h[ep['synopsis']]}</p><p class="meta">Target: #{h[ep['target_words'].to_a.join(', ')]}</p>
  #{panels}</main></body></html>
HTML
puts File.join(dir, "index.html").delete_prefix("#{Probe::ROOT}/")
