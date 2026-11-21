# Spike M.0 of wave M (docs/roadmap.md): light motion in the webtoon reader, see MotionLite.
# MOTION_LITE=ab — half of the readers get it on by default (by analytics id); on — everyone; off — nobody, no setting.
# Tests run with off; the motion system test switches it on.
Rails.application.configure do
  config.x.reader.motion_lite = ENV.fetch("MOTION_LITE", Rails.env.test? ? "off" : "ab")
end
