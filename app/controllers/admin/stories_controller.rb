module Admin
  # User stories (wave 7): what was made, by whom, at what cost, and the moderation actions —
  # hide / bring back (approve) / ban the author. Reports are closed by the same actions.
  class StoriesController < BaseController
    before_action :set_story, except: :index

    def index
      @stories = Series.source_user.includes(:author, :language_pair, :story_requests, episodes: %i[generation_logs translations])
                       .order(created_at: :desc).limit(200)
      @open_reports = Report.open.joins(:episode).group("episodes.series_id").count
      @translation_votes = TranslationRequest.group(:episode_id).count
    end

    def hide
      @story.hidden!
      Report.close_all(@story.episodes, as: :resolved, by: Current.user)
      redirect_back_or_to admin_stories_path, notice: "Скрыта: #{@story.title}"
    end

    def approve
      @story.approved!
      Report.close_all(@story.episodes, as: :dismissed, by: Current.user)
      redirect_back_or_to admin_stories_path, notice: "Возвращена: #{@story.title}"
    end

    # The author's stories disappear for everyone else (StoryAccess, Series.listed); they cannot create new ones.
    def ban_author
      @story.author.update!(banned_at: Time.current)
      Report.close_all(Episode.joins(:series).where(series: { author_id: @story.author_id }), as: :resolved, by: Current.user)
      redirect_back_or_to admin_stories_path, notice: "Автор заблокирован: #{@story.author.author_name}"
    end

    private
      def set_story
        @story = Series.source_user.find(params[:id])
      end
  end
end
