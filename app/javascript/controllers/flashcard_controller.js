import { Controller } from "@hotwired/stimulus"
import { speak, stopSpeaking } from "reader/speech"

// Review card: show the answer, read the word aloud, answer with keys 1–4 (space flips).
export default class extends Controller {
  static targets = [ "flip", "back" ]
  static values = { lang: String, speech: String }

  disconnect() {
    stopSpeaking()
  }

  show() {
    this.backTarget.hidden = false
    this.flipTarget.hidden = true
    this.element.querySelector("[data-flashcard-key='3']")?.focus({ preventScroll: true })
  }

  speak() {
    speak(this.speechValue, this.langValue)
  }

  key(event) {
    if (event.target.closest("input, textarea")) return
    if (this.backTarget.hidden) {
      if (event.key === " " || event.key === "Enter") { event.preventDefault(); this.show() }
      return
    }
    const button = this.element.querySelector(`[data-flashcard-key='${event.key}']`)
    if (button) { event.preventDefault(); button.click() }
  }
}
