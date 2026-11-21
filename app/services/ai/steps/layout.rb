module Ai
  module Steps
    # Pipeline step 3 "Bubbles": places webtoon bubbles in the free top of the picture (the image prompt keeps the top
    # 25% calm). No AI: sizes come from the text length and the reader's CSS (.wt-bubble: font 4.3% of the panel width,
    # padding .55em/.8em, romanization adds a line above Korean words). Bubbles cascade from the top-left corner,
    # alternating sides, like the hand-made seeds. Boxes already set (by hand in the admin) are kept unless force.
    #
    #   Ai::Steps::Layout.call(episode)   # => number of bubbles placed
    class Layout
      FONT = 4.3            # % of the panel width
      PAD_X = 1.6 * FONT    # left + right padding
      PAD_Y = 1.1 * FONT + 0.6
      MARGIN = 4
      GAP = 2
      LINE_EM = { "ko" => 1.95, "default" => 1.35 }.freeze # Korean lines carry romanization on top
      WIDTH = { "narration" => 30..72, "default" => 26..64 }.freeze
      PREFERRED_WIDTH = 56 # longer lines wrap into 2–3 lines of about this width
      WRAP = 1.1           # words do not fill lines completely

      def self.call(episode, **) = new(episode, **).call

      # Width of the text in em: Hangul ≈ 1em, Latin letters ≈ .5em, spaces and punctuation ≈ .3em.
      def self.text_em(text)
        text.to_s.each_char.sum do |char|
          case char
          when /\p{Hangul}|\p{Han}/ then 1.0
          when /[[:upper:]]/ then 0.62
          when /[[:alnum:]]/ then 0.5
          else 0.3
          end
        end
      end

      def initialize(episode, force: false)
        @episode = episode
        @force = force
        @language = episode.series.language_pair.target_lang
      end

      def call
        return 0 if @episode.format_chat?

        GenerationLog.track(step: "layout", episode: @episode) do |log|
          placed = @episode.panels.includes(:bubbles).sum { |panel| place(panel) }
          log.update!(metadata: log.metadata.merge("bubbles" => placed))
          placed
        end
      end

      # Box {x, y, w, h} in percent of the panel for one bubble at the given top and side.
      def box_for(bubble, top:, side:, aspect_ratio:)
        width, lines = width_and_lines(bubble)
        height = ((lines * LINE_EM.fetch(@language, LINE_EM["default"]) * FONT) + PAD_Y) * aspect_ratio
        height = height.ceil.clamp(8, 40)
        x = side == :left ? MARGIN : 100 - MARGIN - width
        { "x" => x, "y" => [ top, 100 - MARGIN - height ].min, "w" => width, "h" => height }
      end

      private
        def place(panel)
          bubbles = panel.bubbles.to_a
          return 0 if bubbles.empty? || (!@force && bubbles.all?(&:box))

          top = MARGIN - 1
          side = :left
          bubbles.sum do |bubble|
            box = (@force || bubble.box.nil?) ? box_for(bubble, top:, side:, aspect_ratio: panel.aspect_ratio) : bubble.box
            changed = box != bubble.box
            bubble.update!(box:) if changed
            top = box["y"] + box["h"] + GAP
            side = side == :left ? :right : :left
            changed ? 1 : 0
          end
        end

        # Short text: one line, as wide as the text. Longer: the fewest lines of about PREFERRED_WIDTH.
        def width_and_lines(bubble)
          range = WIDTH.fetch(bubble.kind, WIDTH["default"])
          text = self.class.text_em(bubble.text) * FONT
          return [ (text + PAD_X + 2).ceil.clamp(range), 1 ] if text + PAD_X + 2 <= PREFERRED_WIDTH

          lines = (text * WRAP / (PREFERRED_WIDTH - PAD_X)).ceil
          width = ((text * WRAP / lines) + PAD_X + 2).ceil.clamp(range)
          lines = (text * WRAP / (width - PAD_X)).ceil # after clamping
          [ width, lines ]
        end
    end
  end
end
