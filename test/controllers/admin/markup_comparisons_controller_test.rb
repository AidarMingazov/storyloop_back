require "test_helper"
require_relative "../../test_helpers/script_test_helper"

class Admin::MarkupComparisonsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ScriptTestHelper
  include TokensTestHelper

  setup do
    sign_in_as users(:admin)
    Ai.reset_fakes!
    Ai::Llm::Fake.respond_with(ko_answer(panels: 2))
    @episode = Ai::Steps::Script.call(ko_series, panels: 2)
  end

  test "the form lists episodes and the configured models; create enqueues the comparison" do
    get admin_markup_comparisons_path
    assert_response :success
    assert_select "select[name=episode_id] option", /Axe · 도끼 #1/
    assert_select "input[name='models[]']", Ai.config.comparison_models.size

    assert_enqueued_with(job: CompareMarkupJob) do
      post admin_markup_comparisons_path, params: { episode_id: @episode.id, models: [ "deepseek:deepseek-flash", "evil:model" ] }
    end
    job = enqueued_jobs.last
    assert_equal [ "deepseek:deepseek-flash" ], job[:args][1], "only configured models"
    assert_redirected_to admin_markup_comparison_path(job[:args][2])

    assert_no_enqueued_jobs { post admin_markup_comparisons_path, params: { episode_id: @episode.id } }
  end

  test "each model's markup is checked and shown side by side; tokens of the episode stay untouched" do
    bubbles = @episode.panels.flat_map(&:bubbles)
    good = markup_answer(bubbles) { |text| ko_tokens(text) }
    bad = markup_answer(bubbles) { |text| ko_tokens(text) }
    bad["bubbles"][0]["tokens"].pop
    Ai::Llm::Fake.respond_with(good, bad)

    Ai::MarkupComparison.run("cmp-1", @episode, [ "openrouter:anthropic/claude-haiku-5.5", "deepseek:deepseek-flash" ])

    logs = Ai::MarkupComparison.logs("cmp-1")
    assert_equal 2, logs.size
    assert logs.all?(&:succeeded?)
    assert_equal [ 3, 4 ], logs.map { |log| log.metadata["clean"] }.sort
    assert_equal 0, @episode.tokens.count

    get admin_markup_comparison_path("cmp-1")
    assert_response :success
    assert_select "th", /claude-haiku-5.5/
    assert_select "td.bg-marker-soft\\/40", 1
    assert_select "td div", /нашёл|not covered: 떨어뜨렸어요/

    get admin_markup_comparisons_path
    assert_select "a[href='#{admin_markup_comparison_path('cmp-1')}']"
  end
end
