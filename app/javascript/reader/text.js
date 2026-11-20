import { h } from "reader/dom"

// Bubble text with each token as a tappable span. Offsets are codepoints (same as Ruby's String#[]),
// so we slice Array.from(text), not the UTF-16 string. Romanization sits in a hidden span under the word
// and is shown only when the reader turns it on (plain inline text otherwise, so selection and copy work).
export function tokenizedText(bubble, { tag = "p", className = "story-text" } = {}) {
  const chars = Array.from(bubble.text)
  const el = h(tag, { class: className })
  let cursor = 0

  for (const token of [...bubble.tokens].sort((a, b) => a.start - b.start)) {
    if (token.start > cursor) el.append(chars.slice(cursor, token.start).join(""))
    const surface = chars.slice(token.start, token.end).join("")
    const span = h("span", { class: "tok", role: "button", tabindex: "0",
                             "data-token-id": token.id, "data-lexeme-id": token.lexeme_id })
    if (token.romanization) {
      span.classList.add("tok--roman")
      span.append(h("span", { class: "tok-base" }, surface), h("span", { class: "tok-rt", "aria-hidden": "true" }, token.romanization))
    } else {
      span.append(surface)
    }
    el.append(span)
    cursor = token.end
  }
  if (cursor < chars.length) el.append(chars.slice(cursor).join(""))
  return el
}
