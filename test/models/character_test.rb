require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  setup do
    @series = Series.create!(language_pair: language_pairs(:ko_en), slug: "char-test", title: "Char test", cefr_level: "A1")
  end

  test "speech level is one of the Korean politeness levels; blank means it depends on the listener" do
    character = @series.characters.create!(key: "a", name: "A", speech_level: "")
    assert_nil character.speech_level

    character.speech_level = "polite"
    assert character.valid?

    character.speech_level = "rude"
    assert_not character.valid?
    assert character.errors.added?(:speech_level, :inclusion, value: "rude")
  end
end
