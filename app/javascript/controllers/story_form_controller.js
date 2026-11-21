import { Controller } from "@hotwired/stimulus"

// "Create a story": shows the inputs of the chosen mode. Without JS every section stays visible and
// the server uses the ones the mode needs; hidden text areas are disabled so they do not send a prompt.
export default class extends Controller {
  static targets = [ "section" ]

  connect() { this.update() }

  update() {
    const mode = this.element.querySelector("input[name='story[mode]']:checked")?.value
    this.sectionTargets.forEach(section => {
      const active = section.dataset.modes.split(" ").includes(mode)
      section.hidden = !active
      section.querySelectorAll("textarea, input").forEach(input => { input.disabled = !active })
    })
  }
}
