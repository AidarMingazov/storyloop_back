import { h } from "reader/dom"
import { icon, setIcon } from "reader/icons"

// End-of-episode screen: the episode's target words (savable right here), counts and next steps.
export function renderSummary(container, { t, words, saved, savedInEpisode, lang, reviewUrl, libraryUrl, next, signupUrl }) {
  // replaceChildren prints null as the text "null", so optional blocks are filtered out (h() skips them itself).
  container.replaceChildren(...[
    h("h2", { class: "summary-title" }, t.summary_title),
    h("div", { class: "summary-stats" },
      h("p", { class: "summary-stat" }, h("b", { "data-summary-new": "" }, String(words.length)), h("span", {}, t.new_words)),
      h("p", { class: "summary-stat" }, h("b", { "data-summary-saved": "" }, String(savedInEpisode)), h("span", {}, t.saved_count))),
    // Guests are asked to sign up right after an episode, when they have something to keep.
    signupUrl ? h("div", { class: "summary-signup", "data-summary-signup": "" },
      h("p", { class: "font-semibold" }, t.signup_title),
      h("p", { class: "reader-muted text-sm" }, t.signup_body),
      h("a", { class: "reader-btn mt-3 w-full", href: signupUrl }, t.signup_cta)) : null,
    words.length ? h("div", { class: "summary-words" }, words.map((word) => wordRow(word, saved.has(word.lexeme.id), t, lang))) : null,
    h("div", { class: "summary-actions" },
      next ? h("a", { class: "reader-btn", href: next.url },
        next.locked ? [ icon("lock"), t.next_locked ] : [ t.next_episode, icon("arrow-right") ]) : null,
      h("a", { class: "reader-btn reader-btn--ghost", href: reviewUrl }, t.review_words),
      h("a", { class: "reader-btn reader-btn--ghost", href: libraryUrl }, t.back_to_library))
  ].filter(Boolean))
}

export function updateSummary(container, { saved, savedInEpisode, t }) {
  const counter = container.querySelector("[data-summary-saved]")
  if (counter) counter.textContent = String(savedInEpisode)
  for (const row of container.querySelectorAll("[data-summary-lexeme]")) {
    const isSaved = saved.has(Number(row.dataset.summaryLexeme))
    row.classList.toggle("is-saved", isSaved)
    const button = row.querySelector("button")
    setIcon(button.querySelector("svg"), isSaved ? "bookmark-fill" : "bookmark")
    button.setAttribute("aria-pressed", String(isSaved))
    button.setAttribute("aria-label", isSaved ? t.saved : t.save_word)
  }
}

function wordRow({ lexeme, token }, isSaved, t, lang) {
  return h("div", { class: `summary-word ${isSaved ? "is-saved" : ""}`, "data-summary-lexeme": lexeme.id },
    h("div", { class: "min-w-0" },
      h("span", { class: "lemma", lang }, lexeme.lemma),
      h("p", { class: "reader-muted text-sm" }, lexeme.translation || token.translation)),
    h("button", { type: "button", class: "reader-btn reader-btn--ghost reader-btn--icon", "aria-pressed": String(isSaved),
                  "aria-label": isSaved ? t.saved : t.save_word,
                  "data-action": "reader#saveFromSummary", "data-lexeme-id": lexeme.id, "data-token-id": token.id },
      icon(isSaved ? "bookmark-fill" : "bookmark")))
}
