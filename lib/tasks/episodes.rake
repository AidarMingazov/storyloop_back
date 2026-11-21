namespace :episodes do
  desc "Import one episode JSON (config/schemas/episode.json). STATUS=published|review (default review)"
  task :import, [ :path ] => :environment do |_t, args|
    path = Pathname(args[:path].presence || abort("Usage: bin/rails 'episodes:import[path/to/episode.json]'"))
    status = ENV.fetch("STATUS", "review")

    episode = Episodes::Importer.call(path.read, status: status, base_dir: path.dirname)
    puts "Imported #{episode.series.title} ##{episode.number} «#{episode.title}» (#{episode.format}, #{status}): " \
         "#{episode.panels.count} panels, #{episode.bubbles.count} bubbles, #{episode.tokens.count} tokens"
  rescue Episodes::Importer::Invalid => e
    abort "#{path}: #{e.message}"
  end

  desc "Import every JSON under DIR (default db/seeds/episodes). STATUS=published|review"
  task :import_all, [ :dir ] => :environment do |_t, args|
    dir = Pathname(args[:dir].presence || Rails.root.join("db/seeds/episodes"))
    Dir[dir.join("**/*.json")].sort.each do |file|
      Rake::Task["episodes:import"].reenable
      Rake::Task["episodes:import"].invoke(file)
    end
  end

  desc "Write a series' voices, character sheets, AI panel images and recordings into its seed JSON + media " \
       "(db/seeds/episodes/<pair>), so db:seed brings them to a fresh database: SERIES=coffee-and-coincidences [DIR=…]"
  task export: :environment do
    series = Series.find_by!(slug: ENV.fetch("SERIES") { abort "SERIES=<slug> is required" })
    summary = Episodes::Exporter.call(series, dir: ENV["DIR"])
    puts "#{series.slug}: " + summary.map { |kind, count| "#{count} #{kind}" }.join(", ")
  rescue Episodes::Exporter::Mismatch => e
    abort "FAILED #{e.message}"
  end
end
