import { h } from "reader/dom"
import { canSpeak } from "reader/speech"

// Bottom sheet with the tapped word (or a whole phrase). Content is rebuilt on every open;
// all data comes from the episode JSON, so it opens without a server round trip.
export class WordSheet {
  constructor(element, t, { onSave, onSpeak, onClose }) {
    this.element = element
    this.t = t
    this.callbacks = { onSave, onSpeak, onClose }
    this.element.addEventListener("click", (event) => this.click(event))
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  showToken({ token, lexeme, saved, lang }) {
    const t = this.t
    const lemmaDiffers = lexeme.lemma.toLowerCase() !== token.surface.toLowerCase()
    const meta = [ t.pos[lexeme.pos] || lexeme.pos, lexeme.cefr_level ].filter(Boolean).join(" · ")
    const romanization = [ token.romanization, lemmaDiffers ? lexeme.romanization : null ].filter(Boolean).join(" → ")

    const chips = []
    for (const part of token.breakdown || []) {
      chips.push(h("span", { class: "sheet-chip" }, h("b", { lang }, part.part), ` · ${t.roles[part.role] || part.role}`,
                   part.meaning ? ` — ${part.meaning}` : null))
    }
    if (token.politeness) chips.push(h("span", { class: "sheet-chip" }, t.politeness[token.politeness]))

    this.render(
      h("div", { class: "sheet-head" },
        h("span", { class: "sheet-word", lang, id: "sheet-title" }, token.surface),
        lemmaDiffers ? h("span", { class: "sheet-lemma", lang }, `→ ${lexeme.lemma}`) : null,
        h("span", { class: "sheet-lemma" }, meta)),
      romanization ? h("p", { class: "sheet-roman" }, romanization) : null,
      h("p", { class: "sheet-translation" }, token.translation),
      lemmaDiffers && lexeme.translation && lexeme.translation !== token.translation
        ? h("p", { class: "sheet-note" }, h("span", { lang }, lexeme.lemma), ` — ${lexeme.translation}`) : null,
      token.note ? h("p", { class: "sheet-note" }, token.note) : null,
      chips.length ? h("div", { class: "sheet-chips" }, chips) : null,
      h("div", { class: "sheet-actions" },
        this.speakButton(),
        h("button", { type: "button", class: "reader-btn", "data-sheet-action": "save", "aria-pressed": String(saved) },
          saved ? `✓ ${t.saved}` : t.save_word)),
      h("p", { class: "sheet-note", "data-sheet-error": "", role: "alert", hidden: true })
    )
    this.open()
  }

  showPhrase({ bubble, lang }) {
    this.render(
      h("p", { class: "sheet-lemma", id: "sheet-title" }, this.t.translate_phrase),
      h("p", { class: "sheet-phrase", lang }, bubble.text),
      h("p", { class: "sheet-translation" }, bubble.translation || "—"),
      h("div", { class: "sheet-actions" }, this.speakButton())
    )
    this.open()
  }

  setSaved(saved) {
    const button = this.element.querySelector("[data-sheet-action=save]")
    if (!button) return
    button.textContent = saved ? `✓ ${this.t.saved}` : this.t.save_word
    button.setAttribute("aria-pressed", String(saved))
  }

  showError(message) {
    const error = this.element.querySelector("[data-sheet-error]")
    if (!error) return
    error.textContent = message
    error.hidden = false
  }

  open() {
    this.element.classList.add("is-open")
    this.element.setAttribute("aria-hidden", "false")
    this.element.setAttribute("aria-labelledby", "sheet-title")
  }

  close() {
    if (!this.isOpen) return
    this.element.classList.remove("is-open")
    this.element.setAttribute("aria-hidden", "true")
    this.callbacks.onClose()
  }

  // private

  render(...children) {
    this.element.replaceChildren(
      h("div", { class: "sheet-grab", "aria-hidden": "true" }),
      h("button", { type: "button", class: "reader-icon-btn sheet-close", "data-sheet-action": "close",
                    "aria-label": this.t.close }, "✕"),
      ...children.filter(Boolean)
    )
    this.element.scrollTop = 0
  }

  speakButton() {
    if (!canSpeak()) return null
    return h("button", { type: "button", class: "reader-btn reader-btn--ghost reader-btn--icon",
                         "data-sheet-action": "speak", "aria-label": this.t.listen, title: this.t.listen }, "🔊")
  }

  click(event) {
    const action = event.target.closest("[data-sheet-action]")?.dataset.sheetAction
    if (action === "save") this.callbacks.onSave()
    if (action === "speak") this.callbacks.onSpeak()
    if (action === "close") this.close()
  }
}
