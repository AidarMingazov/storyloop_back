# POST /episodes/:episode_id/shares { channel } — the share button reports how the link went out.
class SharesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  rate_limit to: 30, within: 1.minute

  CHANNELS = %w[web_share copy].freeze

  def create
    episode = Episode.find(params[:episode_id])
    # Whoever presses Share is looking at the story, so they hold the link.
    return head(:not_found) unless StoryAccess.new(episode, current_reader, via_link: true).readable?

    Episode.update_counters(episode.id, shares_count: 1)
    channel = CHANNELS.include?(params[:channel]) ? params[:channel] : "other"
    track("story_shared", user: current_reader, episode: episode, channel: channel, source: episode.series.source,
                          own: episode.series.author_id == current_reader.id)
    head :no_content
  end
end
