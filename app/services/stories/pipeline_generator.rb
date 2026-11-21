module Stories
  # The AI pipeline for user stories (7.4), following the Stories::Generator contract on top of the wave 6 steps:
  # the cast is copied into the story's series, Stories::Script writes one complete episode from the brief, then
  # images → layout → tokens → audio as for the catalog. No human review: GenerateStoryJob publishes the story after
  # moderation. Every AI call is in GenerationLog with the episode (cost of user generations).
  class PipelineGenerator
    include Generator

    IMAGE_ATTEMPTS = 2

    def initialize(random: Random)
      @random = random
    end

    def call(request)
      episode = request.episode.reload
      return episode if episode.published? # a retried job after everything was done

      series = request.series
      Cast.for(mode: request.mode, theme: request.theme, cast: request.cast_key).cast_into(series)

      request.progress!("script")
      episode = Script.new(request, random: @random).call
      series.update!(title: episode.title) # a story is named by its series (feed, "My stories")

      request.progress!("images")
      draw(episode)
      request.progress!("layout")
      Ai::Steps::Layout.call(episode)
      request.progress!("tokens")
      Ai::Steps::Tokens.call(episode)
      request.progress!("audio")
      Ai::Steps::Audio.call(episode)

      episode.update!(status: :published)
      series.published! if series.draft?
      episode
    end

    private
      # A panel the provider's safety filter refused fails the story as rejected (7.6); other failed panels get one
      # more try, a panel without a picture fails the story (a placeholder is no story to share).
      def draw(episode)
        panels = nil # first: every panel that still has a placeholder
        IMAGE_ATTEMPTS.times do
          result = Ai::Steps::Images.call(episode, panels:)
          rejected = result.failed.values.find { |error| error.is_a?(Ai::ContentRejected) }
          raise Rejected, "image rejected by the provider: #{rejected.message}" if rejected
          return if result.ok?

          panels = result.failed.keys
          @image_error = result.failed.values.first
        end
        raise Ai::Error, "panels #{panels.map { |p| p.position + 1 }.join(', ')} have no picture: #{@image_error.message}"
      end
  end
end
