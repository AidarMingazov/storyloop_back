module Stories
  # Comic from own photos, part 1 (7.11): a vision model looks at the photos (safety, people and animals, places,
  # scenes), the story's series gets the art style of the chosen cast with the photo places as settings, and every
  # person or animal becomes a character with a sheet drawn after their clearest photo. The author then confirms
  # the characters (StoryRequest#await_confirmation!) and the usual pipeline writes and draws the story.
  # Photos without people or animals: the cast's own characters play in the photo places.
  class PhotoCast
    ATTEMPTS = 2
    THREADS = 3
    NAMES = { # defaults on the confirmation screen, the author renames
      "en" => { "person" => %w[Alex Sam Robin], "animal" => %w[Buddy Coco Max] },
      "ko" => { "person" => %w[Haneul Jiwoo Yuna], "animal" => %w[Bori Choco Dubu] }
    }.freeze
    UNSAFE = { "minors" => "minors", "nudity" => "sexual", "violence" => "violence", "public_figure" => "personal" }.freeze

    attr_reader :request

    def self.call(request) = new(request).call

    def initialize(request)
      @request = request
      @series = request.series
      @lang = request.language_pair.target_lang
    end

    def call
      request.progress!("vision")
      photos = Array.new(request.photos.count) { |index| request.photo_jpeg(index) }
      vision = see(photos)
      request.update!(vision:)
      cast = Cast.for(mode: "photos", cast: request.cast_key)
      style!(cast, vision)

      request.progress!("sheets")
      characters = characters!(vision)
      return cast.cast_into(@series).tap { request.update!(vision: vision.merge("cast" => cast.key)) } if characters.empty?

      draw(characters.map { |character, photo| [ character, photos[photo] ] })
      @series
    end

    # A new sheet for one character, from the same photo (confirmation screen).
    def redraw(character)
      PhotoSheet.call(character, request.photo_jpeg(photo_of(character)))
    end

    private
      def see(photos)
        messages = Ai::Prompt.messages("photos", count: photos.size)
        images = photos.map { |bytes| StringIO.new(bytes) }
        vision = GenerationLog.track(step: "vision", episode: request.episode, metadata: { "photos" => photos.size }) do |log|
          json = ATTEMPTS.times.lazy.map { Ai.llm(:vision).chat(messages, json: true, images:, max_tokens: 4_000, temperature: 0.2).json }
                         .find { |answer| answer.is_a?(Hash) && answer["safety"].is_a?(Hash) && answer["subjects"].is_a?(Array) }
          raise Ai::InvalidOutput.new("vision: no description of the photos", problems: [ "the answer had no safety / subjects" ]) unless json

          log.update!(metadata: log.metadata.merge("subjects" => json["subjects"].size, "safety" => json["safety"]))
          json
        end
        unsafe = UNSAFE.find { |flag, _| vision.dig("safety", flag) == true }
        raise Rejected.new("photos: #{unsafe.first}", category: unsafe.last) if unsafe

        vision
      end

      # The cast's drawing style; the settings come from the photos.
      def style!(cast, vision)
        places = Array(vision["places"]).filter_map { |place| place["description"].to_s.squish.presence }.first(5)
        @series.update!(
          art_style: cast.data["art_style"], tone: cast.data["tone"], genre: "slice of life from the learner's photos",
          narrator_voice: cast.data["narrator_voice"].then { |voice| voice.is_a?(Hash) ? voice[@lang] : voice },
          style_prompt: [ cast.data["art_style"].to_s.squish,
                          ("Settings from the learner's photos: #{places.join('; ')}." if places.any?),
                          "Vertical webtoon panel composition.",
                          "No text, letters, numbers, signs, captions or speech bubbles anywhere in the image." ].compact.join(" ")
        )
      end

      # → [[character, photo index]]
      def characters!(vision)
        count = Hash.new(0)
        Array(vision["subjects"]).first(StoryRequest::PHOTO_CHARACTERS).each_with_index.map do |subject, index|
          kind = subject["kind"] == "animal" ? "animal" : "person"
          name = NAMES.fetch(@lang, NAMES["en"]).fetch(kind)[count[kind]]
          count[kind] += 1
          character = @series.characters.find_or_initialize_by(key: "p#{index + 1}")
          character.update!(name: character.name.presence || name, protagonist: index.zero?, speech_level: nil,
                            appearance_prompt: [ subject["look"], subject["outfit"] ].compact_blank.join("; ").squish.truncate(700),
                            voice: StoryRequest::VOICES.dig(subject["voice"] == "male" ? "male" : "female", @lang))
          [ character, photo_index(subject) ]
        end
      end

      def photo_index(subject)
        index = subject["best_photo"].to_i - 1
        index.between?(0, request.photos.count - 1) ? index : 0
      end

      def photo_of(character)
        subject = Array(request.vision["subjects"])[character.key.delete_prefix("p").to_i - 1] || {}
        photo_index(subject)
      end

      # Sheets a few at a time (10–30 s each). A failed sheet fails the step: the confirmation screen needs every one.
      def draw(jobs)
        errors = Concurrent::Array.new
        queue = Queue.new
        jobs.each { |job| queue << job }
        queue.close
        Array.new([ THREADS, jobs.size ].min) do
          Thread.new do
            Rails.application.executor.wrap do
              while (job = queue.pop)
                begin
                  PhotoSheet.call(*job)
                rescue Ai::Error, ArgumentError => e
                  errors << e
                end
              end
            end
          end
        end.each(&:join)
        rejected = errors.find { |error| error.is_a?(Ai::ContentRejected) }
        raise Rejected.new("photo sheet rejected by the provider: #{rejected.message}", category: "images") if rejected
        raise errors.first if errors.any?
      end
  end
end
