module StoriesHelper
  # Where an episode opens. User stories always go through their share link, so "link" stories stay
  # readable for people who got them that way (StoryAccess only lets /s/:token through for those).
  def read_path(episode)
    episode.user_story? ? shared_episode_path(episode.share_token) : episode_path(episode)
  end

  # The link the share button sends: the sharer's public id as `ref`, UTM for the share loop.
  # A path (it is also rendered in Turbo broadcasts, which know no host); share_controller.js makes
  # it absolute and adds utm_medium (web_share / copy).
  def share_path(episode, sharer:)
    shared_episode_path(episode.share_token, ref: sharer&.public_id, utm_source: "share",
                                            utm_campaign: episode.user_story? ? "story" : "episode")
  end

  # The full link shown on the story page to copy by hand.
  def share_link_url(episode, sharer:)
    shared_episode_url(episode.share_token, ref: sharer&.public_id, utm_source: "share", utm_medium: "link",
                                            utm_campaign: episode.user_story? ? "story" : "episode")
  end

  # Private and hidden stories open only for their author: a link would lead others nowhere.
  def shareable?(episode)
    series = episode.series
    !series.user_story? || (!series.visibility_private? && !series.hidden?)
  end

  # Preview card image: the first panel cropped to 1200×630, served directly (some crawlers do not follow redirects).
  def og_image_url(episode)
    panel = episode.panels.with_attached_image.find { |p| p.image.attached? }
    return image_url("/icon.png") unless panel

    rails_storage_proxy_url(panel.image.variant(resize_to_fill: [ 1200, 630 ], format: :jpeg, saver: { quality: 82 }))
  end

  # "Episode · Series", or one of them when they match (a one-episode user story).
  def story_title(episode)
    [ episode.title, episode.series.title ].uniq.join(" · ")
  end

  def pair_label(pair)
    t("stories.pairs.#{pair.code}", default: pair.code)
  end

  def visibility_label(series)
    t("stories.visibility.#{series.visibility}.title")
  end

  def story_status(series)
    episode = series.episodes.first
    request = series.story_requests.max_by(&:created_at)
    return :hidden if series.hidden?
    return :failed if episode&.failed? || request&.failed?
    return :generating unless episode&.published?
    :ready
  end

  def theme_icon(key) = Stories::Themes.icon(key)
end
