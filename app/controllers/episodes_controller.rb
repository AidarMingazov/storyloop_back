class EpisodesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  layout "reader"

  def show
    @episode = Episode.includes(series: [ :language_pair, :characters ]).find(params[:id])
    raise ActiveRecord::RecordNotFound unless @episode.published? || resume_session&.user&.admin?

    pair = @episode.series.language_pair
    @reader = current_reader
    @reader.update!(language_pair: pair) if @reader.language_pair.nil?

    I18n.with_locale(pair.ui_locale) do
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
    def start_reading
      progress = @reader.reading_progresses.find_or_create_by!(episode: @episode)
      track("episode_started", user: @reader, episode: @episode) if progress.previously_new_record?
    rescue ActiveRecord::RecordNotUnique
      retry
    end
end
