# Series and model answers for the scenario step tests.
module ScriptTestHelper
  def ko_series
    @ko_series ||= Series.create!(language_pair: language_pairs(:ko_en), slug: "axe", title: "Axe · 도끼", genre: "folk tale",
                                  cefr_level: "A1", tone: "Ends with the moral.", style_prompt: "Watercolor.").tap do |series|
      series.characters.create!(key: "woodcutter", name: "Woodcutter", protagonist: true, speech_level: "polite", voice: "Korean_InnocentBoy")
      series.characters.create!(key: "spirit", name: "Mountain Spirit", speech_level: "casual")
    end
  end

  def en_series
    @en_series ||= Series.create!(language_pair: language_pairs(:en_ru), slug: "magi", title: "The Gift", genre: "classic",
                                  cefr_level: "A2", tone: "Bittersweet.").tap do |series|
      series.characters.create!(key: "della", name: "Della", protagonist: true)
      series.characters.create!(key: "jim", name: "Jim")
    end
  end

  KO_WORDS = %w[나무꾼 도끼 연못 정직하다 울다].freeze

  # A model answer that passes every check: panels × (narration + speech).
  def ko_answer(panels: 10, title: "금도끼 · The Golden Axe")
    { "episode" => {
      "title" => title, "synopsis" => "An honest woodcutter loses his axe.", "target_words" => KO_WORDS,
      "panels" => Array.new(panels) do |i|
        { "image_prompt" => "Medium shot: Woodcutter by the pond, panel #{i + 1}.",
          "bubbles" => [
            { "kind" => "narration", "character" => nil, "text" => "나무꾼이 연못에 도끼를 떨어뜨렸어요.", "translation" => "The woodcutter dropped his axe." },
            { "kind" => "speech", "character" => "woodcutter", "text" => "정직하게 말해요. 울지 마세요.", "translation" => "I'm honest. Don't cry." }
          ] }
      end
    } }
  end

  def en_chat_answer
    { "episode" => {
      "title" => "One Dollar", "synopsis" => "Della texts Jim.", "target_words" => [ "give up", "gift", "save", "cheap", "can't wait" ],
      "panels" => Array.new(3) do
        { "bubbles" => [
          { "kind" => "chat_message", "character" => "della", "text" => "I can't give up. I want a gift for you!", "translation" => "Я не сдамся. Хочу тебе подарок!" },
          { "kind" => "chat_message", "character" => "jim", "text" => "Save your money. I can't wait to see you.", "translation" => "Береги деньги. Жду встречи." }
        ] }
      end
    } }
  end
end
