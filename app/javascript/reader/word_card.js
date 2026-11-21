import { h } from "reader/dom"
import { icon, setIcon } from "reader/icons"
import { canSpeak } from "reader/speech"

const DESKTOP = "(min-width: 1024px)"
const GAP = 12 // px between the word and its popover

// The card of a tapped word. On a phone it is a bottom sheet that leaves the page scrollable, so the line
// stays readable above it; from 1024px it is a popover anchored to the word. Content is rebuilt on every
// open from the episode JSON, so it shows without a server round trip. Either way the line stays in view.
export class WordCard {
  constructor(element, t, { onSave, onSpeak, onSpeakLine, onClose }) {
    this.element = element
    this.t = t
    this.callbacks = { onSave, onSpeak, onSpeakLine, onClose }
    this.element.addEventListener("click", (event) => this.click(event))
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  get isPopover() {
    return this.element.classList.contains("is-popover")
  }

  // token + lexeme: the word; bubble: its line (translation, audio); anchor: the tapped element.
  show({ token, lexeme, bubble, saved, lang, nativeLang }, anchor) {
    const t = this.t
    const lemmaDiffers = lexeme.lemma.toLowerCase() !== token.surface.toLowerCase()
    const dictionary = lemmaDiffers || (lexeme.translation && lexeme.translation !== token.translation)
    const tags = [ t.pos[lexeme.pos] || lexeme.pos, lexeme.cefr_level, token.politeness && t.politeness[token.politeness] ]
    const popover = window.matchMedia(DESKTOP).matches

    this.element.replaceChildren(...[
      h("div", { class: "sheet-handle", "aria-hidden": "true" }),
      h("div", { class: "wc-head" },
        h("div", { class: "min-w-0" },
          h("p", { class: "wc-word", lang, id: "sheet-title" }, token.surface),
          token.romanization ? h("p", { class: "wc-rom" }, token.romanization) : null),
        h("div", { class: "wc-head-actions" },
          canSpeak() || lexeme.audio_url ? iconButton("sound", "speak", t.listen, "btn-icon-soft") : null,
          iconButton("close", "close", t.close, "btn-icon"))),
      h("div", { class: "wc-tags" }, tags.filter(Boolean).map((tag) => h("span", { class: "tag" }, tag))),
      h("p", { class: "wc-tr", lang: nativeLang }, token.translation),
      dictionary ? h("p", { class: "wc-dict" },
        h("span", { class: "wc-k" }, t.dictionary_form),
        h("b", { lang }, lexeme.lemma),
        lemmaDiffers && lexeme.romanization ? h("span", { class: "wc-lr" }, ` ${lexeme.romanization}`) : null,
        lexeme.translation ? h("span", { lang: nativeLang }, ` — ${lexeme.translation}`) : null) : null,
      token.note ? h("div", { class: "wc-note" },
        h("span", { class: "wc-k" }, t.in_this_sentence),
        h("p", { lang: nativeLang }, token.note)) : null,
      token.breakdown?.length ? h("div", { class: "wc-gram" },
        h("span", { class: "wc-k" }, t.how_built),
        h("ul", {}, token.breakdown.map((part) => h("li", {},
          h("b", { lang }, part.part),
          h("span", { class: "wc-role" }, t.roles[part.role] || part.role),
          h("span", { lang: nativeLang }, part.meaning || ""))))) : null,
      bubble?.translation ? h("button", { type: "button", class: "wc-line", "data-sheet-action": "line-translation", "aria-expanded": "false" },
        icon("eye"),
        h("span", { class: "wc-line-hint" }, t.show_line),
        h("span", { class: "wc-line-text", lang: nativeLang }, bubble.translation)) : null,
      h("div", { class: "wc-acts" },
        h("button", { type: "button", class: saved ? "btn-saved" : "btn-accent", "data-sheet-action": "save", "aria-pressed": String(saved) },
          saveLabel(saved, t)),
        bubble && (bubble.audio_url || canSpeak()) ? h("button", { type: "button", class: "btn-secondary", "data-sheet-action": "speak-line",
                                                                      "aria-label": t.listen_line, title: t.listen_line },
          icon("play"), t.play_line) : null),
      h("p", { class: "wc-error", "data-sheet-error": "", role: "alert", hidden: true }),
      popover ? h("p", { class: "wc-keys", "aria-hidden": "true" },
        h("span", { class: "kbd" }, "S"), t.key_save, h("span", { class: "kbd" }, "L"), t.key_listen,
        h("span", { class: "kbd" }, "Esc"), t.close) : null
    ].filter(Boolean))
    this.element.scrollTop = 0
    this.open(popover ? anchor : null)
  }

  setSaved(saved) {
    const button = this.element.querySelector("[data-sheet-action=save]")
    if (!button) return
    // In place: replacing the nodes would detach the icon the reader has just clicked.
    setIcon(button.querySelector("svg"), saved ? "bookmark-fill" : "bookmark")
    button.lastChild.textContent = saved ? this.t.saved : this.t.save_word
    button.className = saved ? "btn-saved" : "btn-accent"
    button.setAttribute("aria-pressed", String(saved))
  }

  showError(message) {
    const error = this.element.querySelector("[data-sheet-error]")
    if (!error) return
    error.textContent = message
    error.hidden = false
  }

  open(anchor) {
    const el = this.element
    el.classList.toggle("is-popover", Boolean(anchor))
    if (anchor) this.place(anchor)
    else this.clearPlace()
    void el.offsetWidth // lay out this mode's closed state first, so the card animates in from it and not from the other mode's
    el.classList.add("is-open")
    el.setAttribute("aria-hidden", "false")
    el.setAttribute("aria-labelledby", "sheet-title")
  }

  close() {
    if (!this.isOpen) return
    this.element.classList.remove("is-open")
    this.element.setAttribute("aria-hidden", "true")
    this.callbacks.onClose()
  }

  // Height the sheet covers at the bottom of the screen (0 for a popover).
  get coveredHeight() {
    return this.isOpen && !this.isPopover ? this.element.offsetHeight : 0
  }

  // private

  // Under the word's line (its bubble or paragraph), so the whole line stays readable, with the arrow at the
  // word; above the line when there is no room below. Coordinates are relative to the positioned ancestor
  // (.reader), so the popover scrolls with the page and stays at its word.
  place(anchor) {
    const el = this.element
    const host = el.offsetParent || document.body
    const hostRect = host.getBoundingClientRect()
    const word = anchor.getBoundingClientRect()
    const line = (anchor.closest("[data-bubble-id]") || anchor).getBoundingClientRect()
    const width = el.offsetWidth
    const height = el.offsetHeight
    const centre = word.left + word.width / 2 - hostRect.left
    const left = Math.min(Math.max(GAP, centre - width / 2), Math.max(GAP, host.clientWidth - width - GAP))
    const roomBelow = window.innerHeight - line.bottom - GAP * 2
    const roomAbove = line.top - GAP * 2
    const below = height <= roomBelow || roomBelow >= roomAbove

    el.style.left = `${left}px`
    el.style.top = `${(below ? line.bottom + GAP : line.top - height - GAP) - hostRect.top}px`
    el.style.setProperty("--arrow-x", `${Math.min(Math.max(18, centre - left), width - 18)}px`)
    el.classList.toggle("is-above", !below)
  }

  clearPlace() {
    this.element.style.left = this.element.style.top = ""
    this.element.classList.remove("is-above")
  }

  click(event) {
    const button = event.target.closest("[data-sheet-action]")
    const action = button?.dataset.sheetAction
    if (action === "save") this.callbacks.onSave()
    if (action === "speak") this.callbacks.onSpeak()
    if (action === "speak-line") this.callbacks.onSpeakLine()
    if (action === "line-translation") button.setAttribute("aria-expanded", String(button.getAttribute("aria-expanded") !== "true"))
    if (action === "close") this.close()
  }
}

function iconButton(name, action, label, className) {
  return h("button", { type: "button", class: className, "data-sheet-action": action, "aria-label": label, title: label }, icon(name))
}

// Icon and text as separate nodes, so setSaved can update both in place.
const saveLabel = (saved, t) => [ icon(saved ? "bookmark-fill" : "bookmark"), document.createTextNode(saved ? t.saved : t.save_word) ]
