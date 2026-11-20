module ReviewsHelper
  # "<1 мин", "10 мин", "3 ч", "6 д", "2 мес", "1 г"
  def review_interval(seconds)
    seconds = seconds.to_i
    if seconds < 60 then t("review.interval.under_minute")
    elsif seconds < 1.hour then t("review.interval.minutes", count: seconds / 60)
    elsif seconds < 1.day then t("review.interval.hours", count: seconds / 1.hour)
    elsif seconds < 30.days then t("review.interval.days", count: (seconds / 1.day.to_f).round)
    elsif seconds < 365.days then t("review.interval.months", count: (seconds / 30.days.to_f).round)
    else t("review.interval.years", count: (seconds / 365.days.to_f).round)
    end
  end

  # The sentence the word was saved from, with the word marked.
  def review_sentence(token)
    chars = token.bubble.text.chars
    safe_join([
      chars[0...token.start_offset].join,
      tag.mark(chars[token.start_offset...token.end_offset].join, class: "marker text-ink-strong"),
      chars[token.end_offset..].to_a.join
    ])
  end
end
