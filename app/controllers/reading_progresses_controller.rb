class ReadingProgressesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  # PATCH /episodes/:episode_id/progress  { last_panel_position, completed }
  def update
    episode = Episode.published.find(params[:episode_id])
    progress = current_reader.reading_progresses.find_or_initialize_by(episode: episode)

    position = params[:last_panel_position].to_i
    progress.last_panel_position = position if position > progress.last_panel_position
    just_completed = progress.completed_at.nil? && ActiveModel::Type::Boolean.new.cast(params[:completed])
    progress.completed_at = Time.current if just_completed
    progress.save!
    track("episode_completed", user: current_reader, episode: episode) if just_completed

    head :no_content
  end
end
