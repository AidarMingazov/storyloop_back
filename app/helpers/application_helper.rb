module ApplicationHelper
  # Bubble text with every token wrapped in a span. Offsets are codepoints, like String#[].
  def tokenized_text(bubble, token_class: "underline decoration-edge decoration-2 underline-offset-4")
    text = bubble.text
    cursor = 0
    parts = []
    bubble.tokens.select(&:persisted?).sort_by(&:start_offset).each do |token|
      parts << text[cursor...token.start_offset] if token.start_offset > cursor
      parts << tag.span(text[token.start_offset...token.end_offset], class: token_class,
                        title: "#{token.lexeme.lemma} — #{token.context_translation}")
      cursor = token.end_offset
    end
    parts << text[cursor..] if cursor < text.length
    safe_join(parts)
  end

  def status_badge(record)
    tag.span(record.status, class: "badge-#{record.status}")
  end

  def form_errors(record)
    return if record.errors.empty?

    tag.div(class: "flash-alert mb-6", role: "alert") do
      tag.ul(class: "list-disc pl-5") { safe_join(record.errors.full_messages.map { |m| tag.li(m) }) }
    end
  end
end
