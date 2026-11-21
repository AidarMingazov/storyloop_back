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

  namespace :series do
    desc "Load series templates (db/templates/ai/series/*.yml) into the DB: bin/rails \"ai:series:load[folk-golden-axe]\" " \
         "(no name = all). REPLACE_SHEETS=1 overwrites sheets already attached"
    task :load, [ :name ] => :environment do |_, args|
      names = args[:name].present? ? [ args[:name] ] : Ai::SeriesTemplate.names
      names.each do |name|
        series = Ai::SeriesTemplate.load(name, replace_sheets: ENV["REPLACE_SHEETS"].present?)
        sheets = series.characters.order(:id).map { |c| "#{c.key}#{c.sheet.attached? ? '' : ' (no sheet)'}" }
        puts "#{name} → #{series.language_pair.code}/#{series.slug} ##{series.id} [#{series.status}]: #{sheets.join(', ')}"
      end
    end
  end

  desc "Step 1 \"Scenario\": SERIES=golden-axe [NUMBER=next] [FORMAT=webtoon|chat] [PANELS=10] [BRIEF=\"…\"] " \
       "[WORDS=\"a, b\"] → draft episode with placeholder pictures (~$0.01, 30–70 s)"
  task script: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    step = Ai::Steps::Script.new(series, number: ENV["NUMBER"], format: ENV.fetch("FORMAT", "webtoon"), panels: ENV["PANELS"],
                                         brief: ENV["BRIEF"], target_words: ENV.fetch("WORDS", "").split(","))
    episode = step.call
    log = episode.generation_logs.where(step: "script").order(:id).last
    puts "#{series.slug} ##{episode.number} «#{episode.title}» [#{episode.format}, #{episode.status}]: " \
         "#{episode.panels.size} panels, #{episode.bubbles.size} bubbles, target words: #{episode.target_words.join(', ')}"
    puts format("attempts %d, %s, %d ms, $%.4f", step.attempts, log.model, log.duration_ms, log.cost_usd)
    step.warnings.each { |warning| puts "warning: #{warning}" }
  rescue Ai::InvalidOutput, Ai::ProviderError => e
    abort "FAILED #{e.message}"
  end

  desc "Step \"Scene\": tags of what each panel shows for the motion player (~$0.001 per episode). SERIES=golden-axe " \
       "[NUMBER=1] for one series or episode; without SERIES every episode that has untagged panels. FORCE=1 retags"
  task scene: :environment do
    episodes = if ENV["SERIES"].present?
      series = Series.find_by!(slug: ENV["SERIES"])
      ENV["NUMBER"].present? ? [ series.episodes.find_by!(number: ENV["NUMBER"]) ] : series.episodes.to_a
    else
      untagged = Panel.where("scene = '{}'::jsonb").where.not(image_prompt: [ nil, "" ]).select(:episode_id)
      Episode.where.not(format: "chat").where(id: untagged).includes(:series).order(:id).to_a
    end
    total = 0.to_d
    episodes.each do |episode|
      name = "#{episode.series.slug} ##{episode.number}"
      started = GenerationLog.maximum(:id).to_i
      summary = Ai::Steps::Scene.call(episode, force: ENV["FORCE"].present?)
      log = episode.generation_logs.where(step: "scene").where("id > ?", started).last
      next puts("#{name}: nothing to tag") unless log

      total += log.cost_usd
      puts format("%s: tagged %d, %s, %d ms, $%.4f", name, summary["tagged"], log.model, log.duration_ms, log.cost_usd)
      summary["failed"].each { |panel, problems| puts "  panel #{panel}: #{problems.join('; ')}" }
    rescue Ai::Error => e
      puts "#{name}: FAILED #{e.message[0, 300]}"
    end
    puts format("%d episodes, $%.4f", episodes.size, total)
  end

  desc "Step 2 \"Images\": SERIES=golden-axe NUMBER=1 [PANELS=2,5 to redraw these] — panels that still have " \
       "placeholders, 3 at a time (~$0.04 and 10–40 s each)"
  task images: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    episode = series.episodes.find_by!(number: ENV.fetch("NUMBER") { abort "NUMBER=<episode number> is required" })
    positions = ENV.fetch("PANELS", "").split(",").map { |n| n.to_i - 1 }
    panels = episode.panels.where(position: positions).to_a if positions.any?
    result = Ai::Steps::Images.call(episode, panels:)
    logs = episode.generation_logs.where(step: "images").order(:id).last(result.drawn.size + result.failed.size)
    puts "#{series.slug} ##{episode.number}: drawn #{result.drawn.size}, failed #{result.failed.size}, " \
         "$#{format('%.3f', logs.sum(&:cost_usd))}, longest #{logs.filter_map(&:duration_ms).max.to_i} ms"
    result.failed.each { |panel, error| puts "panel #{panel.position + 1}: FAILED #{error.message[0, 200]}" }
  end

  desc "Step 3 \"Bubbles\": SERIES=golden-axe NUMBER=1 [FORCE=1 to redo boxes set by hand] — boxes at the top of each panel"
  task layout: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    episode = series.episodes.find_by!(number: ENV.fetch("NUMBER") { abort "NUMBER=<episode number> is required" })
    puts "#{series.slug} ##{episode.number}: placed #{Ai::Steps::Layout.call(episode, force: ENV['FORCE'].present?)} bubbles"
  end

  desc "Step 4 \"Word markup\": SERIES=golden-axe NUMBER=1 — tokens for every bubble (~$0.01, ~50 s per 20 bubbles)"
  task tokens: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    episode = series.episodes.find_by!(number: ENV.fetch("NUMBER") { abort "NUMBER=<episode number> is required" })
    summary = Ai::Steps::Tokens.call(episode)
    log = episode.generation_logs.where(step: "tokens").order(:id).last
    puts "#{series.slug} ##{episode.number}: #{summary['tokens']} tokens, #{log.model}, #{log.duration_ms} ms, " \
         "$#{format('%.4f', log.cost_usd)}, #{log.metadata['calls']} calls"
    summary["unresolved"].each { |id, problems| puts "unresolved #{id}: #{problems.join('; ')}" }
  end

  desc "Step 5 \"Audio\": SERIES=golden-axe NUMBER=1 [FORCE=1 to re-record bubbles] — bubbles + new dictionary forms"
  task audio: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    episode = series.episodes.find_by!(number: ENV.fetch("NUMBER") { abort "NUMBER=<episode number> is required" })
    summary = Ai::Steps::Audio.call(episode, force: ENV["FORCE"].present?)
    log = episode.generation_logs.where(step: "audio").order(:id).last
    puts "#{series.slug} ##{episode.number}: #{summary['bubbles']} bubbles, #{summary['lemmas']} lemmas, #{log.characters} chars, " \
         "#{log.duration_ms} ms, $#{format('%.4f', log.cost_usd)}"
    summary["failed"].each { |name, error| puts "FAILED #{name}: #{error}" }
  end

  desc "Whole pipeline for new episodes: SERIES=golden-axe [COUNT=1] [FORMAT=webtoon|chat] [PANELS=10] [BRIEF=\"…\"] " \
       "[WORDS=\"a, b\"] — one after another, ~$0.6 and 3–5 min each; BRIEF and WORDS apply to the first"
  task generate: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    episodes = GenerateEpisodeJob.perform_now(series, {
      count: ENV.fetch("COUNT", 1), format: ENV.fetch("FORMAT", "webtoon"), panels: ENV["PANELS"], brief: ENV["BRIEF"],
      target_words: ENV.fetch("WORDS", "").split(",")
    }.compact)
    episodes.each do |episode|
      status = Ai::PipelineStatus.new(episode)
      puts "##{episode.number} «#{episode.title}» [#{episode.status}] $#{format('%.3f', status.total_usd)}"
      status.rows.each { |row| puts format("  %-7s %-9s %s", row.step, row.status, row.notes) }
    end
  end

  desc "Generate character sheets with the image model (~$0.04 each): SERIES=golden-axe [CHARACTERS=woodcutter,spirit] " \
       "[FORCE=1 to redo existing sheets]"
  task sheets: :environment do
    series = Series.where(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" }).to_a
    abort "no series #{ENV['SERIES']}" if series.empty?
    only = ENV.fetch("CHARACTERS", "").split(",").map(&:strip)

    series.flat_map { |s| s.characters.order(:id).to_a }.each do |character|
      next if only.any? && !only.include?(character.key)
      next puts("#{character.key}: sheet exists (FORCE=1 to redo)") if character.sheet.attached? && ENV["FORCE"].blank?

      result = Ai::CharacterSheet.call(character)
      puts format("%-12s %s %d ms $%.3f", character.key, result.model, result.duration_ms, result.cost_usd)
    rescue Ai::Error, ArgumentError => e
      puts "#{character.key}: FAILED #{e.message[0, 200]}"
    end
  end
end
