require "zlib"

# Spike M.0 of wave M (docs/roadmap.md, docs/motion-research.md): light motion in the webtoon reader — a panel's
# picture slowly zooms in as it comes into view and its bubbles appear one by one (reader/motion_lite.js). It asks
# whether motion helps or hurts learning: half of the readers get it on by default, split by analytics id (stable,
# nothing stored); the reader can switch it in the settings. Every analytics event carries the variant
# (motion_variant), reader events also whether motion was really on (motion).
#
#   MotionLite.variant(user.analytics_id)  # => "motion" | "static", nil when the spike is off
module MotionLite
  MODES = %w[ab on off].freeze
  SALT = "motion_lite:" # another experiment on the same ids gets an independent split

  module_function

  def mode
    value = Rails.configuration.x.reader.motion_lite.to_s
    MODES.include?(value) ? value : "off"
  end

  def enabled? = mode != "off"

  def variant(distinct_id)
    case mode
    when "on" then "motion"
    when "ab" then Zlib.crc32("#{SALT}#{distinct_id}").even? ? "motion" : "static" if distinct_id.present?
    end
  end
end
