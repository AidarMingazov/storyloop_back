// Spike M.0 of wave M (docs/roadmap.md, app/models/motion_lite.rb): light motion for the webtoon. When a panel comes
// into view its picture slowly zooms in and its bubbles appear one by one, in reading order. No new data: the
// panel image and the bubble order are enough.
//
// Learning comes first: a bubble that is not shown yet is `visibility: hidden` (no tap lands on an invisible
// word), a tap anywhere on a panel shows the rest of its bubbles at once, and panels the reader has already
// passed (resume) are shown as they are. Only transform and opacity are animated. The caller decides whether
// motion is on (the setting, prefers-reduced-motion) and calls setEnabled when that changes.
const ZOOM = { to: 1.06, duration: 6000, easing: "cubic-bezier(.25,.1,.25,1)", origin: "50% 60%" }
const FIRST_BUBBLE = 350 // ms after the panel comes into view
const BUBBLE_GAP = 750 // ms between bubbles
const BUBBLE_IN = { duration: 380, easing: "cubic-bezier(.2,.8,.2,1)" }
const START_LINE = "0px 0px -35% 0px" // a panel starts when its top passes 65% of the screen height
const HIDDEN = "is-motion-hidden"

export class MotionLite {
  // panels: .wt-panel figures in order. before: panels with a lower position are already read.
  constructor(panels, { enabled = false, before = 0 } = {}) {
    this.panels = panels
    this.timers = new Map() // figure → timeouts of its bubbles
    this.zooms = new Map() // figure → the image animation
    this.onTap = (event) => { if (this.enabled) this.showAll(event.currentTarget) }
    for (const panel of panels) {
      if (Number(panel.dataset.position) < before) panel.dataset.motion = "done"
      panel.addEventListener("click", this.onTap)
    }
    this.enabled = false
    this.setEnabled(enabled)
  }

  setEnabled(enabled) {
    enabled = Boolean(enabled) && "IntersectionObserver" in window && typeof Element.prototype.animate === "function"
    if (enabled === this.enabled) return
    this.enabled = enabled
    enabled ? this.start() : this.stop()
  }

  start() {
    const waiting = this.panels.filter((panel) => panel.dataset.motion !== "done")
    for (const panel of waiting) {
      panel.dataset.motion = "waiting"
      for (const bubble of bubbles(panel)) bubble.classList.add(HIDDEN)
    }
    this.observer = new IntersectionObserver((entries) => {
      for (const entry of entries) if (entry.isIntersecting) this.play(entry.target)
    }, { rootMargin: START_LINE })
    waiting.forEach((panel) => this.observer.observe(panel))
  }

  // Off: everything is shown as it is, nothing moves. Panels not reached yet may still move if motion comes back.
  stop() {
    this.observer?.disconnect()
    this.observer = null
    for (const panel of this.panels) {
      const unseen = panel.dataset.motion === "waiting"
      this.showAll(panel)
      if (unseen) delete panel.dataset.motion
      this.zooms.get(panel)?.cancel()
    }
    this.zooms.clear()
  }

  play(panel) {
    if (panel.dataset.motion !== "waiting") return
    panel.dataset.motion = "playing"
    this.observer?.unobserve(panel)

    const image = panel.querySelector("img")
    if (image) {
      image.style.transformOrigin = ZOOM.origin
      this.zooms.set(panel, image.animate([ { transform: "scale(1)" }, { transform: `scale(${ZOOM.to})` } ],
                                          { duration: ZOOM.duration, easing: ZOOM.easing, fill: "forwards" }))
    }

    const hidden = bubbles(panel)
    const timers = hidden.map((bubble, index) => setTimeout(() => this.show(bubble), FIRST_BUBBLE + index * BUBBLE_GAP))
    timers.push(setTimeout(() => this.finish(panel), FIRST_BUBBLE + hidden.length * BUBBLE_GAP))
    this.timers.set(panel, timers)
  }

  show(bubble) {
    if (!bubble.classList.contains(HIDDEN)) return
    bubble.classList.remove(HIDDEN)
    bubble.animate([ { opacity: 0, transform: "translateY(6px) scale(.97)" }, { opacity: 1, transform: "none" } ], BUBBLE_IN)
  }

  // A tap on a panel (or motion switched off): the rest of its bubbles appear at once, the zoom goes on.
  showAll(panel) {
    for (const timer of this.timers.get(panel) || []) clearTimeout(timer)
    this.timers.delete(panel)
    for (const bubble of bubbles(panel)) bubble.classList.remove(HIDDEN)
    if (panel.dataset.motion !== "done") this.finish(panel)
  }

  finish(panel) {
    panel.dataset.motion = "done"
    this.observer?.unobserve(panel)
  }

  destroy() {
    this.observer?.disconnect()
    for (const timers of this.timers.values()) timers.forEach(clearTimeout)
    for (const panel of this.panels) panel.removeEventListener("click", this.onTap)
  }
}

function bubbles(panel) {
  return [ ...panel.querySelectorAll(".wt-bubble") ]
}
