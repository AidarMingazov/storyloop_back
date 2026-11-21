# Seedream (BytePlus ModelArk) probe: one image, optionally with reference images.
#
#   docker compose exec web ruby script/ai_probe/image.rb "prompt text" [ref1.png ref2.png ...]
#   PROMPT_FILE=db/templates/ai/... ruby script/ai_probe/image.rb - refs...
#
# ENV: ARK_API_KEY (required), SEEDREAM_MODEL (check the exact id in the ModelArk console → Model list),
#      ARK_BASE_URL, SIZE (default 1728x2160 ≈ 4:5 for a webtoon panel; or "2K"), OUT_NAME.
# Reference images may be local files (sent as data URIs) or http(s) URLs.
require_relative "lib"

prompt = ARGV[0] == "-" || ARGV[0].nil? ? File.read(ENV.fetch("PROMPT_FILE") { abort("Usage: image.rb \"prompt\" [refs...]") }) : ARGV[0]
refs = ARGV[1..].to_a.map do |ref|
  next ref if ref.start_with?("http")
  ext = File.extname(ref).delete(".").downcase.sub("jpg", "jpeg")
  "data:image/#{ext};base64,#{Base64.strict_encode64(File.binread(ref))}"
end

model = ENV.fetch("SEEDREAM_MODEL", "seedream-4-5-251128")
base = ENV.fetch("ARK_BASE_URL", "https://ark.ap-southeast.bytepluses.com/api/v3")
body = { model: model, prompt: prompt, size: ENV.fetch("SIZE", "1728x2160"), response_format: "url", watermark: false }
body[:image] = refs.one? ? refs.first : refs if refs.any?

res, sec = Probe.post_json("#{base}/images/generations", body, "Authorization" => "Bearer #{Probe.key!('ARK_API_KEY')}")
p = Probe.price("byteplus", model).then { _1.empty? ? Probe.price("byteplus", "default") : _1 }
images = res["data"].to_a
cost = images.size * p["image"] + [ refs.size - 1, 0 ].max * p["extra_reference"]

paths = images.each_with_index.map do |img, i|
  name = "#{ENV.fetch('OUT_NAME', "img-#{Probe.stamp}")}#{images.size > 1 ? "-#{i + 1}" : ''}.jpeg"
  img["url"] ? Probe.download(img["url"], File.join(Probe::OUT, "images", name)) : Probe.save("images/#{name}", Base64.decode64(img["b64_json"]))
end

puts paths
puts "seedream/#{res['model'] || model}: #{sec}s, #{images.size} image(s), refs #{refs.size}, usage #{res['usage']}, est. cost #{Probe.usd(cost)}"
Probe.log(step: "image", provider: "byteplus", model: res["model"] || model, seconds: sec, refs: refs.size,
          usage: res["usage"], cost_usd: cost, files: paths.map { _1.delete_prefix("#{Probe::ROOT}/") }, prompt: prompt[0, 300])
