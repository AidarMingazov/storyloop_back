require "test_helper"

class StoryAccessTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
    @stranger = users(:guest)
  end

  def readable?(episode, user, via_link: false) = StoryAccess.new(episode, user, via_link: via_link).readable?

  test "catalog: published episodes for everyone, drafts only for admins" do
    episode = catalog_episode
    assert readable?(episode, nil)
    episode.update!(status: :review)
    assert_not readable?(episode, @stranger)
    assert readable?(episode, users(:admin))
  end

  test "visibility: private for the author, link with the token, public for everyone" do
    story = create_story(visibility: "private")
    assert readable?(story, @author)
    assert_not readable?(story, @stranger, via_link: true)

    story.series.update!(visibility: "link")
    assert readable?(story, @stranger, via_link: true)
    assert readable?(story, nil, via_link: true)
    assert_not readable?(story, @stranger), "a link story does not open by id"

    story.series.update!(visibility: "public")
    assert readable?(story, nil)
  end

  test "hidden stories and banned authors: nobody but the author and admins" do
    story = create_story(visibility: "public", moderation_state: "hidden")
    assert_not readable?(story, @stranger, via_link: true)
    assert readable?(story, @author)
    assert readable?(story, users(:admin))

    story.series.approved!
    @author.update!(banned_at: Time.current)
    assert_not readable?(story, @stranger, via_link: true)
  end

  test "a story still being generated is not readable by others; reported stories still open" do
    story = create_story(visibility: "public", status: "generating")
    assert_not readable?(story, @stranger)
    assert StoryAccess.new(story, @author).author?

    story.published!
    story.series.pending!
    assert readable?(story, @stranger), "pending only takes it out of the feed"
    assert_not story.series.listed?
  end
end
