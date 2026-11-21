module Ai
  module Steps
    # Pipeline step 5 "Audio": every bubble in its speaker's voice (narration in series.narrator_voice, thoughts a bit
    # slower) and the dictionary form of every word of the episode that has no recording yet (lexemes are shared, so
    # later episodes need fewer). A few calls at a time; costs and characters go to one GenerationLog. A failed
    # recording is reported, the reader falls back to the browser's speech synthesis for it.
    #
    #   Ai::Steps::Audio.call(episode)  # => {"bubbles" => 18, "lemmas" => 41, "failed" => {}}
    class Audio
      THREADS = 2 # MiniMax answers "1002 rate limit (RPM)" quickly with more
      THOUGHT_SPEED = 0.95

      def self.call(episode, **) = new(episode, **).call

      def initialize(episode, bubbles: nil, force: false, threads: THREADS)
        @episode = episode
        @series = episode.series
        @language = @series.language_pair.target_lang
        all = episode.panels.includes(bubbles: [ :character, { audio_attachment: :blob } ]).flat_map(&:bubbles)
        @bubbles = bubbles || (force ? all : all.reject { |b| b.audio.attached? })
        @lexemes = Lexeme.where(id: episode.tokens.select(:lexeme_id)).with_attached_audio.reject { |l| l.audio.attached? }
        @threads = threads
      end

      def voice_for(bubble)
        voice = bubble.narration? ? @series.narrator_voice : bubble.character&.voice
        voice.presence || default_voice
      end

      def call
        jobs = @bubbles.map { |b| [ "bubble #{b.id}", b, { text: b.text, voice: voice_for(b), speed: b.thought? ? THOUGHT_SPEED : 1.0 } ] } +
               @lexemes.map { |l| [ "lemma #{l.lemma}", l, { text: l.lemma, voice: default_voice } ] }

        GenerationLog.track(step: "audio", episode: @episode) do |log|
          results, failed = run(jobs)
          results.each { |_, result| log.add_call(result) } # recorded here: the worker threads have no current log
          summary = { "bubbles" => results.count { |record, _| record.is_a?(Bubble) },
                      "lemmas" => results.count { |record, _| record.is_a?(Lexeme) }, "failed" => failed }
          log.update!(metadata: log.metadata.merge(summary))
          summary
        end
      end

      private
        def default_voice
          Ai.config.step(:audio).fetch("voices", {}).fetch(@language) { raise ConfigError, "no default voice for #{@language} in config/ai.yml" }
        end

        def run(jobs)
          queue = Queue.new
          jobs.each { |job| queue << job }
          queue.close
          results = Concurrent::Array.new
          failed = Concurrent::Hash.new
          Array.new([ @threads, jobs.size ].min) do
            Thread.new do
              Rails.application.executor.wrap do
                tts = Ai.tts(:audio)
                while (job = queue.pop)
                  name, record, options = job
                  begin
                    result = tts.speak(language: @language, **options)
                    record.audio.attach(result.to_attachable("#{name.parameterize}.#{extension(result)}"))
                    results << [ record, result ]
                  rescue Ai::Error => e
                    failed[name] = e.message.truncate(200)
                  end
                end
              end
            end
          end.each(&:join)
          [ results.to_a, failed.to_h ]
        end

        def extension(result) = Rack::Mime::MIME_TYPES.invert.fetch(result.content_type, ".mp3").delete_prefix(".")
    end
  end
end
