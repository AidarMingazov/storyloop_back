# Picks what to read: the first free episode of the published series closest to the learner's level.
module Library
  module_function

  def first_episode_for(pair, level)
    wanted = Cefr::LEVELS.index(level) || 0
    series = pair.series.catalog.published.includes(:episodes).min_by do |s|
      [ (Cefr::LEVELS.index(s.cefr_level).to_i - wanted).abs, s.position, s.id ]
    end
    series&.episodes&.select(&:published?)&.min_by(&:number)
  end
end
