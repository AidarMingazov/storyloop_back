module Stories
  # Offline stand-in for the AI classifier (Stories::AiModerator): lets everything through except an explicit
  # marker, so tests and demos can see a rejection.
  class FakeModerator
    MARKER = "[[blocked]]"

    def check(text, episode: nil)
      text.to_s.include?(MARKER) ? Verdict.rejected("fake moderator: marker found", category: "other") : Verdict.ok
    end
  end
end
