require "test_helper"

class SharedLinksTest < ActionDispatch::IntegrationTest
  test "a guest opens a link story without an account; the ref is remembered and reaches signup" do
    story = create_story(visibility: "link")
    author = users(:one)

    get shared_episode_path(story.share_token, ref: author.public_id, utm_source: "share", utm_medium: "copy")
    assert_response :success
    assert_select ".reader[data-format=webtoon]"
    assert_select "meta[property='og:title'][content=?]", "Spilled · Cafe story"
    assert_select "meta[property='og:url'][content$=?]", "/s/#{story.share_token}"
    assert_select "meta[name=robots][content=noindex]"
    assert_select "#story-footer", text: /Автор/

    guest = User.last
    assert guest.guest?
    assert_equal author, guest.referrer
    assert_equal({ "utm_source" => "share", "utm_medium" => "copy" }, guest.utm)
    opened = tracked("share_opened").sole[:properties]
    assert_equal [ author.public_id, "user", author.public_id, false, "copy" ],
                 opened.values_at(:ref, :source, :author, :own, :channel)

    post registration_path, params: { email_address: "friend@example.com", password: "secret-pass" }
    assert_equal author.public_id, tracked("signup").sole[:properties][:ref]
  end

  test "manga and illustrated stories follow the same access rule" do
    %w[manga illustrated].each do |format|
      story = create_story(visibility: "link", fixture: "reader_#{format}.json")
      get shared_episode_path(story.share_token)
      assert_response :success
      assert_select ".reader[data-format=#{format}]"

      get episode_path(story)
      assert_response :not_found

      story.series.visibility_private!
      get shared_episode_path(story.share_token)
      assert_response :not_found
    end
  end

  test "a link story does not open by id, a private one not even by link" do
    story = create_story(visibility: "link")
    get episode_path(story)
    assert_response :not_found
    assert_select "#story-unavailable"

    story.series.visibility_private!
    get shared_episode_path(story.share_token)
    assert_response :not_found
    get shared_episode_path("nope")
    assert_response :not_found
  end

  test "the author reads their own private story; a story in progress sends them to its status page" do
    story = create_story(visibility: "private")
    sign_in_as users(:one)
    get shared_episode_path(story.share_token)
    assert_response :success
    assert_select "#own-story", text: /Только я/
    assert_select "#share-button", count: 0

    story.generating!
    get shared_episode_path(story.share_token)
    assert_redirected_to story_path(story.series)
  end

  test "messenger crawlers get the preview card: no guest, no events" do
    story = create_story(visibility: "link")
    assert_no_difference -> { User.count } do
      get shared_episode_path(story.share_token), headers: { "User-Agent" => "TelegramBot (like TwitterBot)" }
    end
    assert_response :success
    assert_select "meta[property='og:description'][content*=?]", "A2"
    assert_select "meta[property='og:image']"
    assert_select "h1", "Spilled"
    assert_empty tracked_events
  end

  test "catalog episodes are shareable right away" do
    episode = catalog_episode
    get shared_episode_path(episode.share_token, ref: users(:one).public_id)
    assert_response :success
    assert_select "#share-button[data-share-url-value*=?]", "utm_campaign=episode"
    assert_select "#report", count: 0
    assert_equal "catalog", tracked("share_opened").sole[:properties][:source]
  end

  test "sharing is counted with its channel" do
    story = create_story(visibility: "link")
    get shared_episode_path(story.share_token)
    post episode_shares_path(story), params: { channel: "web_share" }, as: :json
    assert_response :no_content
    assert_equal 1, story.reload.shares_count
    assert_equal "web_share", tracked("story_shared").sole[:properties][:channel]

    story.series.visibility_private!
    post episode_shares_path(story), params: { channel: "copy" }, as: :json
    assert_response :not_found
  end

  test "reading progress needs access, unless the reader already opened the story" do
    story = create_story(visibility: "link")
    patch episode_progress_path(story), params: { last_panel_position: 1 }
    assert_response :not_found

    get shared_episode_path(story.share_token)
    patch episode_progress_path(story), params: { last_panel_position: 1, completed: true }
    assert_response :no_content
    assert_equal 1, story.reload.reads_count
  end
end
