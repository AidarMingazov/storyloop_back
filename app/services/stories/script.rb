module Stories
  # Pipeline step 1 "Scenario" for a user story (7.4): Ai::Steps::Script (checks, retries with feedback, import into the
  # story's series as episode 1) with the story prompt — one complete episode from the learner's brief. When the brief
  # has its own characters, the model maps them onto the cast and the copies in this series take the learner's names.
  class Script < Ai::Steps::Script
    PANELS = { "webtoon" => 6, "chat" => 3 }.freeze
    NAME = /\A[\p{Latin}][\p{Latin} .'-]{0,29}\z/
    # "Surprise me" picks from or mixes a few of these.
    IDEAS = [
      "a lost item that turns out to be magic", "a wrong order that changes someone's day", "a secret admirer",
      "a rainy day in a stranger's shop", "a pet that runs away during an important event", "a mysterious neighbor",
      "a festival night", "a trip where everything goes wrong", "an old letter found in a book", "a cooking contest",
      "a job interview with a surprise", "a time-travel mix-up", "a talent show", "a power cut in a big building",
      "a message sent to the wrong person", "a treasure map from a grandparent", "a robot that wants a hobby",
      "a camping night with strange sounds", "a first day in a new city", "a birthday surprise that almost fails"
    ].freeze

    def initialize(request, random: Random)
      @request = request
      @random = random
      super(request.series, number: 1, format: request.format, panels: PANELS.fetch(request.format), brief: request.prompt)
    end

    def messages
      Ai::Prompt.messages(
        "story",
        target: @target, native: @native, cefr: series.cefr_level, format:, panels:, genre: series.genre,
        tone: series.tone.to_s, characters:, mode: @request.mode, theme: @request.theme_title,
        idea: (@request.prompt if @request.mode_idea? || @request.mode_photos?), text: (@request.prompt if @request.mode_text?),
        ideas: IDEAS.sample(4, random: @random), avoid:,
        scenes: Array(@request.vision["scenes"]).first(StoryRequest::PHOTO_LIMIT), hooks: Array(@request.vision["story_hooks"]).first(3),
        language_rules: Ai::Prompt.render("languages/#{@target.code}", cefr: series.cefr_level, native: @native)
      )
    end

    private
      def document(json)
        rename(json["cast"]) if json.is_a?(Hash) && !@request.mode_photos? # photo characters are named by the author
        super
      end

      # {"jun" => "Pasha"}: the series copy of the character is called as in the learner's brief.
      def rename(cast)
        return unless cast.is_a?(Hash)

        taken = series.characters.pluck(:key, :name).to_h
        cast.each do |key, name|
          name = name.to_s.squish
          next unless taken.key?(key) && name.match?(NAME) && (taken.except(key).values.map(&:downcase) & [ name.downcase ]).empty?

          series.characters.find_by!(key:).update!(name:)
          taken[key] = name
        end
      end

      # Titles of the author's earlier stories: "surprise me" and ideas should not repeat them.
      def avoid
        @request.previous_requests.includes(:series).filter_map { |r| r.series&.title if r.succeeded? }.uniq.first(10)
      end
  end
end
