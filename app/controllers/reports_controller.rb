# POST /episodes/:episode_id/reports — "Report" in the reader (7.6). The story leaves the feed until a
# moderator looks at it (Report#pull_from_feed); the reporter does not see it any more.
class ReportsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  rate_limit to: 10, within: 10.minutes, with: -> { redirect_to community_path, alert: t("stories.report.rate_limited") }

  def create
    episode = Episode.find(params[:episode_id])
    return head(:not_found) unless episode.user_story?

    report = current_reader.reports.find_or_initialize_by(episode: episode)
    report.assign_attributes(reason: params[:reason], comment: params[:comment].to_s.strip.presence)
    if report.save
      track("story_reported", user: current_reader, episode: episode, reason: report.reason, author: episode.author.public_id)
      redirect_to community_path, notice: t("stories.report.thanks")
    else
      redirect_back_or_to read_path(episode), alert: t("stories.report.invalid")
    end
  end

  private
    def read_path(episode) = helpers.read_path(episode)
end
