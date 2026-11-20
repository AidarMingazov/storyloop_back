# Idempotent: safe to run again after editing seed JSON.
#   docker compose run --rm web bin/rails db:seed

[
  { code: "en-ru", target_lang: "en", native_lang: "ru" },
  { code: "ko-en", target_lang: "ko", native_lang: "en" }
].each do |attrs|
  LanguagePair.find_or_create_by!(code: attrs[:code]) { |pair| pair.assign_attributes(attrs) }
end

if Rails.env.development?
  User.find_or_create_by!(email_address: "admin@storyloop.local") do |user|
    user.password = "storyloop-admin"
    user.admin = true
  end
end

Dir[Rails.root.join("db/seeds/episodes/**/*.json")].sort.each do |file|
  episode = Episodes::Importer.call(File.read(file), status: "published", base_dir: File.dirname(file))
  puts "seeded #{episode.series.slug} ##{episode.number} (#{episode.format}, #{episode.tokens.count} tokens)"
rescue Episodes::Importer::Invalid => e
  warn "skipped #{file}: #{e.message}"
end
