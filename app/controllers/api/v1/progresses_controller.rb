module Api
  module V1
    class ProgressesController < BaseController
      before_action :require_user!

      # PATCH /api/v1/episodes/:episode_id/progress  { last_panel_position, completed }
      def update
        episode = Episode.published.find(params[:episode_id])
        progress = current_user.reading_progresses.find_or_initialize_by(episode: episode)
        position = params[:last_panel_position].to_i
        progress.last_panel_position = position if position > progress.last_panel_position
        just_completed = progress.completed_at.nil? && ActiveModel::Type::Boolean.new.cast(params[:completed])
        progress.completed_at = Time.current if just_completed
        progress.save!
        track("episode_completed", episode: episode) if just_completed
        render json: { last_panel_position: progress.last_panel_position, completed: progress.completed? }
      end
    end
  end
end
