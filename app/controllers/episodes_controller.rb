class EpisodesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  layout "reader"

  # GET /episodes/:id, and GET /s/:share_token — the share link: opens without an account (a guest is
  # created on the first visit) and carries the OG preview for messengers. StoryAccess decides who may read.
  def show
    @episode = find_episode or return render_unavailable
    @via_link = params[:share_token].present?
    access = StoryAccess.new(@episode, resume_session&.user, via_link: @via_link)
    return render_unavailable unless access.readable?
    return redirect_to(story_path(@episode.series)) if access.author? && !@episode.published?
    # Messenger crawlers only need the OG tags: no guest user, no events for every link preview.
    return render(:preview, layout: "application") if LinkPreview.crawler?(request.user_agent)

    pair = @episode.series.language_pair
    @reader = current_reader
    @reader.update!(language_pair: pair) if @reader.language_pair.nil?
    @author = access.author?

    I18n.with_locale(pair.ui_locale) do
      track_share_opened if shared_link?
      if @reader.can_read?(@episode)
        start_reading
        @payload = EpisodePayload.new(@episode, user: @reader)
        render :show
      else
        track("paywall_viewed", user: @reader, episode: @episode)
        @plans = Pricing.for(pair)
        render :paywall, layout: "application"
      end
    end
  end

  private
    def find_episode
      scope = Episode.includes(series: [ :language_pair, :characters, :author ])
      params[:share_token] ? scope.find_by(share_token: params[:share_token]) : scope.find(params[:id])
    end

    def render_unavailable
      render :unavailable, layout: "application", status: :not_found
    end

    def start_reading
      progress = @reader.reading_progresses.find_or_create_by!(episode: @episode)
      track("episode_started", user: @reader, episode: @episode) if progress.previously_new_record?
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # A link someone sent (share button or copied link carry ref / utm_source=share) — not the
    # feed or "My stories", which also open user stories through /s/:token, and not the author.
    def shared_link?
      @via_link && !@author && (params[:ref].present? || params[:utm_source] == "share")
    end

    def track_share_opened
      ref = params[:ref].presence
      track("share_opened", user: @reader, episode: @episode, ref: ref, source: @episode.series.source,
                            author: @episode.author&.public_id, own: ref.present? && ref == @reader.public_id,
                            channel: params[:utm_medium].presence)
    end
end
