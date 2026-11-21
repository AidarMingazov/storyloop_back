namespace :ai do
  desc "Show which provider/model each AI step uses and whether its key is present (never prints keys)"
  task config: :environment do
    config = Ai.config
    puts "force_provider: #{config.forced_provider || '-'}"
    config.steps.each do |step|
      settings = config.step(step)
      provider = config.forced_provider || settings["provider"]
      key = if provider == "fake" then "-"
      else
        begin
          config.api_key(provider) && "key ok"
        rescue Ai::ConfigError
          "NO KEY"
        end
      end
      puts format("%-13s %-11s %-36s %s", step, provider, settings["model"], key)
    end
  end

  desc "Live smoke test: one tiny real call per step and its cost. STEPS=script,tokens,vision,audio (images costs ~$0.04)"
  task smoke: :environment do
    steps = ENV.fetch("STEPS", "script,tokens,audio").split(",").map(&:strip)
    picture = Ai::Image::Fake.new(step: "smoke").generate(prompt: "smoke").image # input for vision, not logged
    steps.each do |step|
      log_step = { "tokens" => "tokens", "script" => "script", "vision" => "vision", "audio" => "audio",
                   "images" => "images", "sheets" => "sheets", "photo_sheets" => "sheets" }.fetch(step)
      result = GenerationLog.track(step: log_step, metadata: { "smoke" => true }) do
        case step
        when "script", "tokens"
          Ai.llm(step).chat([ { role: "user", content: 'Return {"word": <one Korean noun>, "en": <its meaning>} as JSON.' } ],
                            json: true, max_tokens: 2_000)
        when "vision"
          Ai.llm(:vision).chat([ { role: "user", content: 'Describe this picture in 5 words as JSON {"text": "…"}.' } ],
                               json: true, images: [ picture.io ], max_tokens: 1_000)
        when "audio"
          Ai.tts(:audio).speak(text: "안녕하세요!", voice: "Korean_SweetGirl", language: "ko")
        else
          # Seedream 4.5 / 5.x need at least 1920×1920 pixels (3.69 MP)
          Ai.image(step).generate(prompt: "A small red apple on a white table, flat webtoon style. No text.", size: "1920x1920")
        end
      end
      detail = result.respond_to?(:text) ? result.text.to_s.squish[0, 80] : result.class.name
      puts format("%-7s %-10s %-34s %6d ms  $%.5f  %s", step, result.provider, result.model, result.duration_ms,
                  result.cost_usd, detail)
    rescue Ai::Error => e
      puts format("%-7s FAILED %s", step, e.message[0, 200])
    end
  end
end
