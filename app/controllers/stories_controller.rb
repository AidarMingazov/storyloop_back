# "My stories" and "Create a story" (7.3), with the free-generation limit and its fake door (7.5).
# A story here is the user's Series; its status comes from the latest StoryRequest.
class StoriesController < ApplicationController
  allow_unauthenticated_access only: :new
  before_action :require_author, except: :new
  before_action :set_story, only: %i[show update destroy reset_link]
  rate_limit to: 5, within: 1.minute, only: :create, with: -> { redirect_to stories_path, alert: t("stories.new.rate_limited") }

  def index
    @stories = Current.user.stories.includes(:language_pair, :story_requests, :episodes).order(created_at: :desc)
    @left = Current.user.story_generations_left
  end

  def new
    @reader = resume_session&.user
    if @reader.nil? || @reader.guest?
      session[:return_to_after_authenticating] = new_story_url
      return render :signup_required
    end
    return redirect_to(stories_path, alert: t("stories.new.banned")) if @reader.banned?
    return render_limit if @reader.story_generations_left <= 0

    @form = StoryForm.new(user: @reader, pair: @reader.language_pair&.code || LanguagePair.active.first&.code,
                          cefr_level: StoryRequest::LEVELS.include?(@reader.self_level) ? @reader.self_level : "A1")
  end

  def create
    return redirect_to(stories_path, alert: t("stories.new.banned")) if Current.user.banned?
    return render_limit if Current.user.story_generations_left <= 0

    @reader = Current.user
    @form = StoryForm.new(form_params.merge(user: @reader))
    if (story_request = @form.submit)
      GenerateStoryJob.perform_later(story_request)
      track("story_created", episode: story_request.episode, mode: story_request.mode, theme: story_request.theme,
                             visibility: story_request.series.visibility, prompt_length: story_request.prompt.to_s.length,
                             generations_left: @reader.story_generations_left.then { |left| left.finite? ? left : nil })
      redirect_to story_path(story_request.series)
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Generation status (live over Turbo Streams), the link, visibility, delete.
  def show
    @episode = @story.episodes.first
    @story_request = @story.story_requests.order(:created_at).last
  end

  # PATCH { visibility }
  def update
    visibility = params[:visibility].to_s
    return redirect_to(story_path(@story)) unless StoryForm::VISIBILITIES.include?(visibility)

    was_public = @story.visibility_public?
    @story.update!(visibility: visibility)
    if @story.visibility_public? && !was_public
      track("story_published", episode: @story.episodes.first, listed: @story.listed?)
    end
    redirect_to story_path(@story), notice: t("stories.show.visibility_saved", visibility: helpers.visibility_label(@story))
  end

  def destroy
    @story.destroy!
    redirect_to stories_path, notice: t("stories.show.deleted"), status: :see_other
  end

  # The old link stops working.
  def reset_link
    @story.episodes.first.reset_share_token!
    redirect_to story_path(@story), notice: t("stories.show.link_reset")
  end

  private
    def require_author
      redirect_to new_story_path if Current.user.guest?
    end

    def set_story
      @story = Current.user.stories.find(params[:id])
    end

    def form_params
      params.expect(story: %i[mode theme prompt text_file pair cefr_level format visibility display_name rules_accepted])
    end

    def render_limit
      @reader ||= Current.user || resume_session&.user
      pair = @reader.language_pair || LanguagePair.active.first
      @plans = Pricing.for(pair)
      track("paywall_viewed", user: @reader, reason: "generation")
      render :limit, status: (request.post? ? :unprocessable_entity : :ok)
    end
end
