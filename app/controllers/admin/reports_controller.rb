module Admin
  # The report queue (7.6): open reports grouped by story, oldest first.
  class ReportsController < BaseController
    def index
      @reports = Report.open.includes(:reporter, episode: { series: :author }).order(:created_at)
      @by_story = @reports.group_by { |report| report.episode.series }
    end
  end
end
