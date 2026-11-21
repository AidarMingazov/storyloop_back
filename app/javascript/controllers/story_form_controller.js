import { Controller } from "@hotwired/stimulus"

// "Create a story": shows the inputs of the chosen mode. Without JS every section stays visible and
// the server uses the ones the mode needs; hidden text areas are disabled so they do not send a prompt.
// A comic from photos is private by default (real people), unless the author picked the visibility themselves.
export default class extends Controller {
  static targets = [ "section" ]

  connect() {
    // a form sent back with errors keeps what the author chose
    const checked = this.element.querySelector("input[name='story[visibility]']:checked")?.value
    this.visibilityChosen = Boolean(checked && checked !== "link")
    this.update()
  }

  update() {
    const mode = this.element.querySelector("input[name='story[mode]']:checked")?.value
    this.sectionTargets.forEach(section => {
      const active = section.dataset.modes.split(" ").includes(mode)
      section.hidden = !active
      section.querySelectorAll("textarea, input").forEach(input => { input.disabled = !active })
    })
    if (!this.visibilityChosen) this.visibility(mode === "photos" ? "private" : "link")
  }

  chooseVisibility() { this.visibilityChosen = true }

  visibility(value) {
    const radio = this.element.querySelector(`input[name='story[visibility]'][value='${value}']`)
    if (radio) radio.checked = true
  }
}
