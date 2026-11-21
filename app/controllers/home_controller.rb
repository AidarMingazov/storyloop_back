class HomeController < ApplicationController
  allow_unauthenticated_access

  def show
    @reader = resume_session&.user
    return redirect_to(start_path) unless @reader&.onboarded? || @reader&.admin?

    @pairs = LanguagePair.active.includes(catalog_series: :episodes).order(:code)

    @due_today = @reader.user_words.due_today.count
    @progress = @reader.reading_progresses.index_by(&:episode_id)
    @continue = continue_reading
  end

  private
    # The unfinished episode read last, or the next episode after the last finished one.
    def continue_reading
      last = @reader.reading_progresses.includes(episode: :series).order(updated_at: :desc).first
      return unless last

      if last.completed?
        following = last.episode.next_episode
        following && { episode: following, next: true }
      else
        episode = last.episode
        total = episode.format_chat? ? episode.bubbles.count : episode.panels.count
        { episode: episode, next: false, done: [ last.last_panel_position + 1, total ].min, total: total }
      end
    end
end
