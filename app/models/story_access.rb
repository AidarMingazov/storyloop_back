# Who may open an episode — the one rule for the web reader, share links, reading progress and
# JSON API v1 (episodes and progress).
#
#   catalog            → published episodes, as before (the paywall decides what is free);
#   user story, author → always, even generating, failed or hidden by moderation;
#   hidden / banned    → nobody else;
#   public             → everyone (the feed additionally needs `approved`, see Series#listed?);
#   link               → whoever opened it through /s/:share_token;
#   private            → only the author.
class StoryAccess
  attr_reader :episode, :user

  def initialize(episode, user, via_link: false)
    @episode = episode
    @user = user
    @via_link = via_link
  end

  def readable?
    return true if user&.admin?
    return true if author?
    return false unless episode.published?
    return true unless series.user_story?
    return false if series.hidden? || series.author.banned?

    series.visibility_public? || (series.visibility_link? && @via_link)
  end

  def author? = series.user_story? && user.present? && series.author_id == user.id

  private
    def series = episode.series
end
