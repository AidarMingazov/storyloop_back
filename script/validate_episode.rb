# Validates episode JSON files without touching the database.
#   docker compose run --rm -T web bundle exec ruby script/validate_episode.rb db/seeds/episodes/**/*.json
#
# Checks: JSON Schema, character keys, format-specific rules, token surfaces found in order
# (or matching explicit offsets), no overlapping tokens.
require "json"
require "json_schemer"

SCHEMA = JSONSchemer.schema(Pathname.new(File.expand_path("../config/schemas/episode.json", __dir__)))

def check(path)
  data = JSON.parse(File.read(path))
  errors = SCHEMA.validate(data).map { |e| "schema: #{e["error"]} at #{e["data_pointer"]}" }
  return errors if errors.any?

  keys = data["series"]["characters"].map { |c| c["key"] }
  format = data["episode"]["format"]

  data["episode"]["panels"].each_with_index do |panel, pi|
    panel["bubbles"].each_with_index do |bubble, bi|
      where = "panel #{pi + 1} bubble #{bi + 1}"
      text = bubble["text"]
      if bubble["character"] && !keys.include?(bubble["character"])
        errors << "#{where}: unknown character #{bubble["character"].inspect}"
      end
      errors << "#{where}: chat episodes use kind chat_message" if format == "chat" && bubble["kind"] != "chat_message"
      errors << "#{where}: chat_message only in chat episodes" if format != "chat" && bubble["kind"] == "chat_message"
      errors << "#{where}: missing box" if %w[webtoon manga].include?(format) && bubble["box"].nil?

      cursor = 0
      (bubble["tokens"] || []).each do |token|
        surface = token["surface"]
        start = token["start"] || text.index(surface, cursor)
        if start.nil?
          errors << "#{where}: token #{surface.inspect} not found after offset #{cursor} in #{text.inspect}"
          next
        end
        finish = token["end"] || start + surface.length
        if text[start...finish] != surface
          errors << "#{where}: offsets #{start}...#{finish} give #{text[start...finish].inspect}, not #{surface.inspect}"
        elsif start < cursor
          errors << "#{where}: token #{surface.inspect} overlaps the previous one"
        end
        cursor = finish
      end
    end
  end
  errors
end

failed = false
ARGV.each do |path|
  errors = check(path)
  if errors.empty?
    puts "ok   #{path}"
  else
    failed = true
    puts "FAIL #{path}"
    errors.each { |e| puts "     #{e}" }
  end
rescue JSON::ParserError => e
  failed = true
  puts "FAIL #{path}: invalid JSON (#{e.message[0, 120]})"
end
exit(failed ? 1 : 0)
