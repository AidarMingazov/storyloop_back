require "test_helper"

class CommunityControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public = create_story(visibility: "public", title: "Public one")
  end

  def feed_titles
    css_select("#community-feed article").map { |card| card.at_css(".font-serif").text.strip }
  end

  test "only public, approved stories of authors in good standing; never the catalog" do
    create_story(visibility: "link", title: "By link")
    create_story(visibility: "private", title: "Private")
    create_story(visibility: "public", moderation_state: "pending", title: "Reported")
    create_story(visibility: "public", moderation_state: "hidden", title: "Hidden")
    create_story(visibility: "public", status: "generating", title: "Generating")
    banned = User.create!(email_address: "bad@example.com", banned_at: Time.current)
    create_story(visibility: "public", author: banned, title: "Banned")
    catalog_episode

    get community_path
    assert_response :success
    assert_equal [ "Public one" ], feed_titles
    assert_select "#community-feed a[href=?]", shared_episode_path(@public.share_token)
  end

  test "filters by pair and level, sorts by popularity" do
    korean = create_story(visibility: "public", fixture: "reader_chat.json", title: "Korean chat")
    popular = create_story(visibility: "public", title: "Popular", cefr_level: "B1")
    popular.update_columns(reads_count: 5, saves_count: 1)

    get community_path(pair: "ko-en")
    assert_equal [ "Korean chat" ], feed_titles
    get community_path(pair: "", level: "B1")
    assert_equal [ "Popular" ], feed_titles
    get community_path(pair: "", sort: "popular")
    assert_equal "Popular", feed_titles.first
    assert_includes feed_titles, korean.series.title
  end

  test "the reader's pair is the default filter" do
    create_story(visibility: "public", fixture: "reader_chat.json", title: "Korean chat")
    user = users(:one)
    user.update!(language_pair: language_pairs(:ko_en))
    sign_in_as user
    get community_path
    assert_equal [ "Korean chat" ], feed_titles
  end

  test "author page lists their public stories; hidden authors and reported stories disappear for the reader" do
    author = users(:one)
    get author_path(author.public_id)
    assert_select "#author-name", author.author_name
    assert_select "#author-stories article", 1

    post author_block_path(author.public_id)
    assert_redirected_to community_path
    assert_equal author.public_id, tracked("author_hidden").sole[:properties][:author]
    get community_path
    assert_empty feed_titles
    get author_path(author.public_id)
    assert_select "#author-hidden"

    delete author_block_path(author.public_id)
    get community_path
    assert_equal [ "Public one" ], feed_titles
  end
end
