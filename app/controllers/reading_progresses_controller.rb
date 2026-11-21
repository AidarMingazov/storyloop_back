class ReadingProgressesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  # PATCH /episodes/:episode_id/progress  { last_panel_position, completed, motion }
  # motion — whether the light motion of spike M.0 was on (webtoon only), goes into episode_completed.
  def update
    episode = Episode.published.find(params[:episode_id])
    progress = current_reader.reading_progresses.find_or_initialize_by(episode: episode)
    # Progress starts when the reader page opens (after StoryAccess); a new one here needs the same check.
    return head(:not_found) if progress.new_record? && !StoryAccess.new(episode, current_reader).readable?

    position = params[:last_panel_position].to_i
    progress.last_panel_position = position if position > progress.last_panel_position
    just_completed = progress.completed_at.nil? && ActiveModel::Type::Boolean.new.cast(params[:completed])
    progress.completed_at = Time.current if just_completed
    progress.save!
    motion = ActiveModel::Type::Boolean.new.cast(params[:motion]) if params.key?(:motion)
    track("episode_completed", user: current_reader, episode: episode, motion:) if just_completed

    head :no_content
  end
end
