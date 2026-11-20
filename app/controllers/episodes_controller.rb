class EpisodesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  layout "reader"

  def show
    @episode = Episode.includes(series: [ :language_pair, :characters ]).find(params[:id])
    raise ActiveRecord::RecordNotFound unless @episode.published? || resume_session&.user&.admin?

    @reader = current_reader
    @reader.update!(language_pair: @episode.series.language_pair) if @reader.language_pair.nil?
    I18n.with_locale(@episode.series.language_pair.ui_locale) do
      if @reader.can_read?(@episode)
        @payload = EpisodePayload.new(@episode, user: @reader)
        render :show
      else
        render :locked
      end
    end
  end
end
