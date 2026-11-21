module Stories
  # Stand-in for the AI pipeline (wave 6): turns a seed episode of the pair into the user's story,
  # with placeholder art and zero-cost GenerationLog rows. Follows the Stories::Generator contract,
  # so switching STORY_GENERATOR to the pipeline changes nothing around it.
  class FakeGenerator
    include Generator

    SEEDS = Rails.root.join("db/seeds/episodes")
    STEPS = %w[script images tokens audio].freeze

    def initialize(step_delay: Stories.config.fake_step_delay)
      @step_delay = step_delay
    end

    def call(request)
      template = pick_template(request)
      data = JSON.parse(File.read(template))

      STEPS.each do |step|
        request.progress!(step)
        sleep @step_delay if @step_delay.positive?
      end

      episode = Episodes::Importer.call(rewrite(data, request), status: "published", base_dir: File.dirname(template))
      log_costs(episode)
      episode
    end

    # One character per photo (up to PHOTO_CHARACTERS) with a placeholder sheet; no vision, no safety check.
    def cast_from_photos(request)
      PhotoCast::NAMES["en"]["person"].first([ request.photos.count, StoryRequest::PHOTO_CHARACTERS ].min).each_with_index do |name, index|
        request.progress!(index.zero? ? "vision" : "sheets")
        character = request.series.characters.find_or_initialize_by(key: "p#{index + 1}")
        character.update!(name:, protagonist: index.zero?, appearance_prompt: "Person from photo #{index + 1}",
                          voice: StoryRequest::VOICES.dig("female", request.language_pair.target_lang))
        redraw_sheet(request, character)
      end
      request.update!(vision: { "fake" => true, "scenes" => [ "photo 1: friends on a trip" ] })
    end

    def redraw_sheet(request, character)
      sleep @step_delay if @step_delay.positive?
      bytes = Episodes::PlaceholderImage.render(16 / 9.0, character.key.sum + request.redraws)
      character.sheet.attach(io: StringIO.new(bytes), filename: "#{character.key}-sheet.webp", content_type: "image/webp")
    end

    private
      # Seed episodes of the pair in the requested format; a different one for each request.
      def pick_template(request)
        files = Dir[SEEDS.join(request.language_pair.code, "*.json")].sort
        matching = files.select { |file| JSON.parse(File.read(file)).dig("episode", "format") == request.format }
        pool = matching.presence || files
        raise Rejected, "no seed episodes for #{request.language_pair.code}" if pool.empty?
        pool[request.id % pool.size]
      end

      def rewrite(data, request)
        series = request.series
        data.merge(
          "language_pair" => request.language_pair.code,
          "series" => data["series"].merge("slug" => series.slug, "title" => series.title, "cefr_level" => request.cefr_level,
                                           "genre" => request.theme || data.dig("series", "genre")),
          # The story is named after the brief; the episode keeps the seed's own title.
          "episode" => data["episode"].merge("number" => 1, "free" => true, "cefr_level" => request.cefr_level)
        )
      end

      def log_costs(episode)
        episode.generation_logs.where(provider: "fake").delete_all # a retried job logs once
        STEPS.each do |step|
          episode.generation_logs.create!(step: step, provider: "fake", model: "fake", status: :succeeded, cost_usd: 0,
                                          duration_ms: (@step_delay * 1000).round)
        end
      end
  end
end
