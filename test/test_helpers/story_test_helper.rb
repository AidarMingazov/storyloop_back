# Builds user stories (wave 7) from the reader fixture: a series of source "user" with episode #1.
module StoryTestHelper
  def create_story(author: users(:one), visibility: "link", moderation_state: "approved", status: "published",
                   fixture: "reader_webtoon.json", title: "Cafe story", cefr_level: nil, pair: nil)
    data = JSON.parse(file_fixture(fixture).read)
    data["language_pair"] = pair if pair
    data["series"].merge!("slug" => "u-#{SecureRandom.hex(4)}", "title" => title) # a story is named by its series
    data["series"]["cefr_level"] = cefr_level if cefr_level
    data["episode"]["free"] = true
    data["episode"]["cefr_level"] = cefr_level if cefr_level
    episode = Episodes::Importer.call(data, status: status)
    episode.series.update!(source: "user", author: author, visibility: visibility, moderation_state: moderation_state)
    episode
  end

  def catalog_episode
    @catalog_episode ||= Episodes::Importer.call(file_fixture("reader_webtoon.json").read, status: "published")
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include StoryTestHelper
end
