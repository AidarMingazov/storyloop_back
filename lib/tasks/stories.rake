# User stories (wave 7). Casts: db/templates/ai/casts/*.yml (README there).
namespace :stories do
  namespace :casts do
    desc "Casts and their sheets: which are missing"
    task check: :environment do
      Stories::Cast.all.each do |cast|
        missing = cast.characters.reject { |character| cast.sheet_path(character) }.map { |character| character["key"] }
        puts format("%-10s %-22s %s", cast.key, cast.title(:en), missing.any? ? "missing sheets: #{missing.join(', ')}" : "ok")
      end
    end

    desc "Draw missing cast sheets with the sheets step model (~$0.04 each) and upload them. CAST=school CHARACTER=jiwoo FORCE=1"
    task sheets: :environment do
      casts = ENV["CAST"].present? ? [ Stories::Cast.fetch(ENV["CAST"]) ] : Stories::Cast.all
      casts.each do |cast|
        series = Series.new(slug: "cast-#{cast.key}", art_style: cast.data["art_style"], style_prompt: cast.data["style_prompt"])
        cast.characters.each do |attrs|
          next if ENV["CHARACTER"].present? && attrs["key"] != ENV["CHARACTER"]
          next if cast.sheet_path(attrs) && ENV["FORCE"].blank?

          path = Stories::Cast::TEMPLATES.join(attrs.fetch("sheet"))
          character = Character.new(series:, key: attrs["key"], name: cast.name_for(attrs, "en"), appearance_prompt: attrs["appearance_prompt"].to_s.squish)
          prompt = Ai::CharacterSheet.new(character).prompt
          # an animal or a creature: the sheet prompt speaks of a person, and the model adds one next to it
          prompt = "#{prompt.gsub('Identical person', 'Identical creature')}\nOnly this one creature: no humans, no riders, no other characters." if attrs["creature"]
          result = GenerationLog.track(step: "sheets", metadata: { "cast" => cast.key, "character" => attrs["key"] }) do
            Ai.image(:sheets).generate(prompt:, size: Ai::CharacterSheet::SIZE)
          end
          FileUtils.mkdir_p(path.dirname)
          path.binwrite(result.image.io.read)
          puts "#{cast.key}/#{attrs['key']}: #{path.relative_path_from(Rails.root)} ($#{result.cost_usd.round(3)})"
        end
      end
      Rake::Task["stories:casts:upload"].invoke
    end

    desc "Upload cast sheets as blobs (shown on the form, attached to every story with that cast)"
    task upload: :environment do
      Stories::Cast.all.each { |cast| cast.characters.each { |character| cast.sheet_blob(character) } }
      puts "uploaded"
    end
  end
end
