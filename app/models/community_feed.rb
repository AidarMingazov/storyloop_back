# The community feed (7.7): public, approved stories of authors who are not banned, minus what the
# reader hid (authors) or reported. Filter by pair and level, sort by new or popular.
class CommunityFeed
  SORTS = %w[new popular].freeze
  PER_PAGE = 20

  attr_reader :pair, :level, :sort, :page

  def initialize(reader: nil, pair: nil, level: nil, sort: nil, page: 1, author: nil)
    @reader = reader
    @pair = pair
    @level = Cefr::LEVELS.include?(level) ? level : nil
    @sort = SORTS.include?(sort) ? sort : "new"
    @page = [ page.to_i, 1 ].max
    @author = author
  end

  def episodes
    @episodes ||= scope.order(order).limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE)
                       .includes(series: %i[author language_pair], panels: { image_attachment: { blob: :variant_records } }).to_a
  end

  def items = episodes.first(PER_PAGE)
  def next_page? = episodes.size > PER_PAGE

  private
    def scope
      relation = Episode.published.joins(:series).merge(Series.listed)
      relation = relation.where(series: { language_pair_id: pair.id }) if pair
      relation = relation.where(cefr_level: level) if level
      relation = relation.where(series: { author_id: @author.id }) if @author
      if @reader
        relation = relation.where.not(series: { author_id: @reader.author_blocks.select(:author_id) })
        relation = relation.where.not(id: @reader.reports.select(:episode_id))
      end
      relation
    end

    def order
      if sort == "popular"
        [ Arel.sql("episodes.reads_count + 2 * episodes.saves_count DESC"), { published_at: :desc } ]
      else
        { published_at: :desc, id: :desc }
      end
    end
end
