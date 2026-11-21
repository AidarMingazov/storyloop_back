module Ai
  module Steps
    # Pipeline step 2 "Images" for an episode: every panel that still has a placeholder (or the given panels), a few
    # at a time — Seedream takes 10–40 s per picture. A failed panel keeps its placeholder and is reported; the others
    # are kept. Chat episodes have no pictures.
    #
    #   Ai::Steps::Images.call(episode)                       # => Result(drawn: [panel…], failed: {panel => error})
    #   Ai::Steps::Images.call(episode, panels: [panel])      # redraw one panel
    class Images
      THREADS = 3
      Result = Data.define(:drawn, :failed) do
        def ok? = failed.empty?
      end

      def self.call(episode, **) = new(episode, **).call

      def initialize(episode, panels: nil, threads: THREADS)
        @episode = episode
        @panels = panels || episode.panels.includes(:bubbles, image_attachment: :blob).select(&:needs_image?)
        @threads = threads
      end

      def call
        missing = @episode.series.characters.reject { |c| c.sheet.attached? }
        Rails.logger.warn("[ai] images: no sheets for #{missing.map(&:key).join(', ')} — drawn without references") if missing.any?

        drawn = Concurrent::Array.new
        failed = Concurrent::Hash.new
        queue = Queue.new
        @panels.each { |panel| queue << panel }
        queue.close

        Array.new([ @threads, @panels.size ].min) do
          Thread.new do
            Rails.application.executor.wrap do
              while (panel = queue.pop)
                begin
                  PanelImage.call(panel)
                  drawn << panel
                rescue Ai::Error, ArgumentError => e
                  failed[panel] = e
                end
              end
            end
          end
        end.each(&:join)

        Result.new(drawn: drawn.sort_by(&:position), failed: failed.sort_by { |panel, _| panel.position }.to_h)
      end
    end
  end
end
