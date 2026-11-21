module Stories
  # Stand-in for the text classifier (7.6, wave 6). Lets everything through except an explicit marker,
  # so tests and demos can see a rejection.
  class FakeModerator
    MARKER = "[[blocked]]"

    def check(text)
      text.to_s.include?(MARKER) ? Verdict.rejected("fake moderator: marker found") : Verdict.ok
    end
  end
end
