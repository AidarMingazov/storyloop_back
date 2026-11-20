require "vips"

module Episodes
  # Draws a simple scene (sky gradient, sun, hill, two figures) so the reader can be built
  # and tested without AI images. Deterministic per series + panel position.
  module PlaceholderImage
    WIDTH = 800
    SKIES = [
      [ [ 247, 201, 160 ], [ 251, 238, 219 ] ], # peach morning
      [ [ 190, 220, 245 ], [ 236, 245, 252 ] ], # day
      [ [ 214, 196, 238 ], [ 245, 236, 250 ] ], # lilac
      [ [ 199, 232, 204 ], [ 240, 249, 240 ] ], # mint
      [ [ 42, 33, 86 ], [ 119, 103, 216 ] ]     # night
    ].freeze
    SUN = [ 255, 137, 4 ].freeze
    HILL = [ 201, 185, 154 ].freeze
    INK = [ 74, 69, 64 ].freeze

    module_function

    def for(panel)
      seed = "#{panel.episode.series&.slug}-#{panel.episode.number}-#{panel.position}".sum
      { io: StringIO.new(render(panel.aspect_ratio, seed)), filename: "placeholder-#{panel.position + 1}.webp",
        content_type: "image/webp" }
    end

    def render(aspect_ratio, seed)
      width = WIDTH
      height = (width / aspect_ratio).round
      top, bottom = SKIES[seed % SKIES.size]

      y = Vips::Image.xyz(width, height).extract_band(1) / height.to_f
      sky = Vips::Image.bandjoin(3.times.map { |i| (y * (bottom[i] - top[i])) + top[i] }).cast(:uchar)

      sun_x = width * (0.55 + ((seed % 7) * 0.05))
      figure_x = width * (0.18 + ((seed % 5) * 0.06))

      image = sky.mutate do |m|
        m.draw_circle!(SUN, sun_x.round, (height * 0.18).round, (width * 0.09).round, fill: true)
        m.draw_circle!(HILL, width / 2, (height * 1.55).round, (height * 0.75).round, fill: true)
        draw_figure(m, figure_x.round, height)
        draw_figure(m, (figure_x + (width * 0.28)).round, height)
      end
      image.webpsave_buffer(Q: 70)
    end

    def draw_figure(m, x, height)
      body_w = 56
      body_h = (height * 0.16).round
      base = (height * 0.86).round
      m.draw_rect!(INK, x - (body_w / 2), base - body_h, body_w, body_h, fill: true)
      m.draw_circle!(INK, x, base - body_h - 30, 30, fill: true)
    end
  end
end
