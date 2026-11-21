import { prefersReducedMotion } from "reader/dom"

// Page turner for paged formats (manga). Replaces the native scroll-snap pager with our own gesture
// so a turn can be drawn with depth: the page follows the finger, then settles with an animation.
//
// The page at rest stays in normal flow and gives the viewport its height; the page being turned to
// is laid over it (position: absolute). Pages off stage are `hidden`, so their lazy images do not
// load until they become a neighbour (see preloadNeighbours).
//
// Effects draw a forward turn A → B at progress v (0 = A, 1 = B). A backward turn is the same
// drawing with A and B swapped and v reversed, so every effect is written once.
//
// Theming: pages get `--pager-page-bg` as background (stacked pages must be opaque), the back of a
// curled page uses `--pager-back` (falls back to the page background).

export const PAGE_TURN_EFFECTS = [ "slide", "curl", "none" ]

const DRAG_SLOP = 8          // px before a touch counts as a drag
const COMMIT_DISTANCE = 0.35 // share of the travel that turns the page on release
const FLICK_SPEED = 0.35     // px/ms that turns the page whatever the distance
const EDGE_GUARD = 24        // px at the left edge left to the system "back" swipe (iOS Safari, Hotwire Native)
const TAP_ZONE = 0.3         // left and right thirds turn pages on tap; the middle is onCenterTap
const DURATION = { slide: 340, curl: 600, fade: 240, none: 0 }
const RELEASE_DURATION_NONE = 160
const PAGE_BG = "var(--pager-page-bg, Canvas)"
const BACK_BG = `var(--pager-back, ${PAGE_BG})`

const clamp = (x, min = 0, max = 1) => Math.min(max, Math.max(min, x))
const easeOut = (t) => 1 - (1 - t) ** 3
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2)
const px = (n) => `${n}px`
// `hidden` alone loses to an author `display: grid` without a reset; inline display makes it certain.
const setShown = (el, shown) => {
  el.hidden = !shown
  el.style.display = shown ? "" : "none"
}
const DRAWINGS = { none: "drawPlain", slide: "drawSlide", fade: "drawFade", curl: "drawCurl" }

export class Pager {
  // pages: elements already inside viewport.
  // onChange(index, previousIndex) fires once a turn settles on a new page (also after goTo without animation).
  // canTap(event) can veto a tap-to-turn (e.g. the first tap only closes the word sheet).
  // tapIgnore: extra selector of elements whose taps belong to someone else (tokens, bubbles).
  constructor(viewport, pages, { index = 0, effect = "slide", onChange, onCenterTap, canTap, tapIgnore } = {}) {
    this.viewport = viewport
    this.pages = pages
    this.onChange = onChange
    this.onCenterTap = onCenterTap
    this.canTap = canTap || (() => true)
    this.tapIgnore = [ "a", "button", "input", "select", "textarea", "label", "summary", "[role=button]", tapIgnore ]
      .filter(Boolean).join(", ")
    this.setEffect(effect)
    this.index = clamp(index, 0, pages.length - 1)
    this.turn = null
    this.gesture = null
    this.frameRequest = null

    this.prepare()
    this.listen()
    this.rest(this.index)
  }

  setEffect(name) {
    this.effect = PAGE_TURN_EFFECTS.includes(name) ? name : "slide"
  }

  get isTurning() {
    return Boolean(this.turn)
  }

  next() { this.turnTo(this.index + 1) }
  previous() { this.turnTo(this.index - 1) }

  goTo(index, { animate = true } = {}) {
    if (index < 0 || index >= this.pages.length) return
    this.finish()
    if (index === this.index) return
    if (!animate) return this.settleOn(index)
    this.begin(index)
    this.animateTo(1, { tap: true })
  }

  destroy() {
    this.finish()
    this.unlisten()
    this.layer.remove()
    for (const page of this.pages) { page.removeAttribute("style"); page.hidden = false }
    for (const prop of [ "position", "display", "overflowX", "isolation", "touchAction", "userSelect", "minHeight" ]) this.viewport.style[prop] = ""
  }

  // ── Setup ────────────────────────────────────────────────

  prepare() {
    const vs = this.viewport.style
    vs.position = "relative"
    vs.display = "block"
    vs.isolation = "isolate"
    vs.touchAction = "pan-y pinch-zoom"
    vs.overflowX = "hidden"
    vs.overflowX = "clip" // keeps vertical overflow visible where supported: a taller incoming page is not cut

    for (const page of this.pages) {
      Object.assign(page.style, { top: "0", left: "0", width: "100%", background: PAGE_BG, backfaceVisibility: "hidden" })
    }

    // Shadows and the back of a curled page. Decorative only.
    const fx = (extra) => {
      const el = document.createElement("div")
      el.setAttribute("aria-hidden", "true")
      el.inert = true
      el.hidden = true
      Object.assign(el.style, { position: "absolute", top: "0", left: "0", pointerEvents: "none" }, extra)
      return el
    }
    this.dim = fx({ width: "100%", background: "#000" })
    this.castShade = fx({ width: "44px", background: "linear-gradient(to right, transparent, rgba(0,0,0,.22))" })
    this.foldShade = fx({ width: "70px", background: "linear-gradient(to right, rgba(0,0,0,.3), transparent)" })
    this.flap = fx({ overflow: "hidden", boxShadow: "0 0 22px rgba(0,0,0,.28)",
                     background: `linear-gradient(to right, rgba(0,0,0,.16), rgba(0,0,0,0) 22%, rgba(255,255,255,.1) 78%, rgba(0,0,0,.16)), ${BACK_BG}` })
    this.layer = document.createElement("div")
    this.layer.append(this.dim, this.castShade, this.foldShade, this.flap)
    this.layer.style.display = "contents"
    this.viewport.append(this.layer)
  }

  listen() {
    this.handlers = {
      pointerdown: (e) => this.pointerDown(e),
      pointermove: (e) => this.pointerMove(e),
      pointerup: (e) => this.pointerUp(e),
      pointercancel: (e) => this.pointerUp(e, { cancelled: true }),
      dragstart: (e) => e.preventDefault(), // native image drag would steal the pointer on desktop
      click: (e) => this.tap(e)
    }
    for (const [ type, handler ] of Object.entries(this.handlers)) this.viewport.addEventListener(type, handler)
    // A drag that started on a word must not open the word sheet when it ends.
    this.swallowClick = (e) => {
      if (!this.suppressClick) return
      this.suppressClick = false
      e.preventDefault()
      e.stopImmediatePropagation()
    }
    this.viewport.addEventListener("click", this.swallowClick, true)
  }

  unlisten() {
    for (const [ type, handler ] of Object.entries(this.handlers)) this.viewport.removeEventListener(type, handler)
    this.viewport.removeEventListener("click", this.swallowClick, true)
  }

  // ── Turning ──────────────────────────────────────────────

  turnTo(target) {
    this.finish()
    if (target < 0 || target >= this.pages.length) return this.bounce(target > this.index ? 1 : -1)
    this.begin(target)
    this.animateTo(1, { tap: true })
  }

  // Shows the current page and the target, measures them, picks the drawing.
  begin(target) {
    const forward = target > this.index
    const current = this.pages[this.index], next = this.pages[target]
    const [ A, B ] = forward ? [ current, next ] : [ next, current ]
    const reduced = prefersReducedMotion()
    const effect = reduced && this.effect !== "none" ? "fade" : this.effect

    for (const page of this.pages) {
      const shown = page === A || page === B
      if (page.hidden === shown) setShown(page, shown)
    }
    for (const page of [ A, B ]) page.style.willChange = "transform, opacity"

    this.turn = { target, forward, A, B, effect, p: 0, width: this.viewport.clientWidth,
                  heightA: A.offsetHeight, heightB: B.offsetHeight }
    // Room for the taller of the two, so an incoming longer page does not spill over what follows.
    this.viewport.style.minHeight = px(Math.max(this.turn.heightA, this.turn.heightB))
    if (effect === "curl") this.flap.replaceChildren(this.ghostOf(A))
  }

  // p: 0 = page at rest, 1 = target.
  draw(p) {
    const turn = this.turn
    turn.p = p
    const v = turn.forward ? p : 1 - p
    this.clearFrame()
    this[DRAWINGS[turn.effect]](turn.A, turn.B, v, turn)
  }

  clearFrame() {
    for (const page of [ this.turn.A, this.turn.B ]) {
      Object.assign(page.style, { transform: "", opacity: "", clipPath: "", boxShadow: "", zIndex: "", transformOrigin: "" })
      page.style.position = page === this.pages[this.index] ? "relative" : "absolute"
    }
    this.dim.hidden = this.castShade.hidden = this.foldShade.hidden = this.flap.hidden = true
  }

  drawPlain(A, B, v, { width }) {
    A.style.transform = `translateX(${-v * width}px)`
    B.style.transform = `translateX(${(1 - v) * width}px)`
  }

  // The leaving page slides away on top with a shadow; the next one comes out from under it slower.
  drawSlide(A, B, v, { width, heightB }) {
    B.style.zIndex = 1
    B.style.transform = `translateX(${(1 - v) * width * 0.3}px)`
    this.show(this.dim, { zIndex: 2, height: px(heightB), opacity: (0.25 * (1 - v)).toFixed(3) })
    A.style.zIndex = 3
    A.style.transform = `translateX(${-v * width}px)`
    A.style.boxShadow = `10px 0 26px rgba(0,0,0,${(0.28 * Math.min(1, v * 6)).toFixed(3)})`
  }

  // Calm fallback for prefers-reduced-motion: a short shift and a cross-fade.
  drawFade(A, B, v) {
    A.style.zIndex = 1
    A.style.transform = `translateX(${-24 * v}px)`
    A.style.opacity = clamp(1 - v / 0.45).toFixed(3)
    B.style.zIndex = 2
    B.style.transform = `translateX(${24 * (1 - v)}px)`
    B.style.opacity = clamp((v - 0.3) / 0.7).toFixed(3)
  }

  // A flat fold: the right edge of A travels to `edge`, the fold sits halfway between it and the
  // right side. A is cut at the fold; the folded strip (its back, with the page showing through
  // mirrored) lies over it, and B is revealed to the right of the fold.
  drawCurl(A, B, v, { width, heightA, heightB }) {
    const fold = width * (1 - v), edge = width * (1 - 2 * v)
    B.style.zIndex = 1
    A.style.zIndex = 2
    A.style.clipPath = `inset(0 ${width - fold}px 0 0)`
    if (v <= 0 || v >= 1) return

    this.show(this.foldShade, { zIndex: 3, left: px(fold), height: px(heightB), opacity: Math.sin(Math.PI * v).toFixed(3) })
    if (edge > -44) this.show(this.castShade, { zIndex: 3, left: px(edge - 44), height: px(heightA), opacity: Math.min(1, v * 4).toFixed(3) })
    this.show(this.flap, { zIndex: 4, left: px(edge), width: px(fold - edge), height: px(heightA) })
    // Mirror A around the fold line: x → 2·fold − x, shifted into the flap's own coordinates.
    Object.assign(this.flap.firstChild.style, { left: px(-edge), width: px(width), transform: `translateX(${2 * fold}px) scaleX(-1)` })
  }

  show(el, style) {
    el.hidden = false
    Object.assign(el.style, style)
  }

  ghostOf(page) {
    const ghost = page.cloneNode(true)
    setShown(ghost, true)
    ghost.removeAttribute("id")
    ghost.removeAttribute("aria-label")
    Object.assign(ghost.style, { position: "absolute", top: "0", opacity: "0.12", transformOrigin: "0 0", background: "none",
                                 clipPath: "", boxShadow: "", zIndex: "", willChange: "" })
    return ghost
  }

  animateTo(target, { tap = false } = {}) {
    const turn = this.turn
    const from = turn.p
    const distance = Math.abs(target - from)
    const base = turn.effect === "none" ? (tap ? 0 : RELEASE_DURATION_NONE) : DURATION[turn.effect]
    const duration = base * Math.max(0.4, distance)
    if (!duration || !distance) return this.settle(target === 1)

    const ease = tap && turn.effect === "curl" ? easeInOut : easeOut
    const start = performance.now()
    turn.goal = target
    const step = (now) => {
      const t = clamp((now - start) / duration)
      this.draw(from + (target - from) * ease(t))
      if (t < 1) this.frameRequest = requestAnimationFrame(step)
      else this.settle(target === 1)
    }
    this.frameRequest = requestAnimationFrame(step)
  }

  // Jump to the end of a running turn (a new tap or drag interrupts it).
  finish() {
    if (!this.turn) return
    cancelAnimationFrame(this.frameRequest)
    this.settle(this.turn.goal === undefined ? false : this.turn.goal === 1)
  }

  settle(turned) {
    const target = this.turn.target
    this.turn = null
    this.flap.replaceChildren()
    if (turned) this.settleOn(target)
    else this.rest(this.index)
  }

  settleOn(index) {
    const previous = this.index
    this.rest(index)
    if (this.viewport.getBoundingClientRect().top < 0) this.viewport.scrollIntoView({ block: "start" })
    this.onChange?.(index, previous)
  }

  // Only the current page is shown, in normal flow, with no leftovers of a drawing.
  rest(index) {
    cancelAnimationFrame(this.frameRequest)
    this.index = index
    this.viewport.style.minHeight = ""
    this.pages.forEach((page, i) => {
      Object.assign(page.style, { transform: "", opacity: "", clipPath: "", boxShadow: "", zIndex: "", transformOrigin: "",
                                  willChange: "", position: i === index ? "relative" : "absolute" })
      setShown(page, i === index)
    })
    this.dim.hidden = this.castShade.hidden = this.foldShade.hidden = this.flap.hidden = true
    this.preloadNeighbours()
  }

  // Off-stage pages are hidden, so lazy images there never start; neighbours must be ready before a swipe.
  preloadNeighbours() {
    for (const page of [ this.pages[this.index - 1], this.pages[this.index + 1] ]) {
      page?.querySelectorAll('img[loading="lazy"]').forEach((img) => { img.loading = "eager" })
    }
  }

  // Tap or key at the first/last page: a short nudge instead of nothing.
  bounce(direction) {
    if (prefersReducedMotion()) return
    this.pages[this.index].animate(
      [ { transform: "none" }, { transform: `translateX(${-direction * 24}px)` }, { transform: "none" } ],
      { duration: 360, easing: "cubic-bezier(.3,.7,.3,1)" })
  }

  // ── Gestures ─────────────────────────────────────────────

  pointerDown(e) {
    this.suppressClick = false
    if (!e.isPrimary || e.button !== 0) return
    if (e.pointerType === "touch" && e.clientX < EDGE_GUARD) return
    if (e.target.closest("input, textarea, select")) return
    this.gesture = { id: e.pointerId, x0: e.clientX, y0: e.clientY, samples: [ [ e.clientX, e.timeStamp ] ], dragging: false }
  }

  pointerMove(e) {
    const g = this.gesture
    if (!g || e.pointerId !== g.id) return
    const dx = e.clientX - g.x0, dy = e.clientY - g.y0
    g.samples.push([ e.clientX, e.timeStamp ])
    if (g.samples.length > 12) g.samples.shift()

    if (!g.dragging) {
      if (Math.hypot(dx, dy) < DRAG_SLOP) return
      if (Math.abs(dy) > Math.abs(dx)) { this.gesture = null; return } // vertical: the page scrolls
      this.startDrag(g, dx, e)
    }

    if (g.edge) {
      const width = this.viewport.clientWidth
      const pull = (dx * 0.6) / (1 + Math.abs(dx) / (width * 0.35))
      this.pages[this.index].style.transform = `translateX(${pull}px)`
      return
    }
    if (!this.turn) { this.gesture = null; return } // the turn was finished by a key or button meanwhile
    const travel = this.turn.width * (this.turn.effect === "curl" ? 1.25 : 1)
    this.draw(clamp((g.forward ? -dx : dx) / travel))
  }

  startDrag(g, dx, e) {
    this.finish()
    g.dragging = true
    g.forward = dx < 0
    const target = this.index + (g.forward ? 1 : -1)
    g.edge = target < 0 || target >= this.pages.length
    if (!g.edge) this.begin(target)
    this.viewport.style.userSelect = "none"
    window.getSelection?.()?.removeAllRanges()
    try { this.viewport.setPointerCapture(e.pointerId) } catch {}
  }

  pointerUp(e, { cancelled = false } = {}) {
    const g = this.gesture
    if (!g || e.pointerId !== g.id) return
    this.gesture = null
    if (!g.dragging) return // a tap: handled by the click that follows
    this.suppressClick = true // the click (if any) comes right after pointerup; never let the flag outlive it
    setTimeout(() => { this.suppressClick = false })
    this.viewport.style.userSelect = ""

    if (g.edge) {
      const page = this.pages[this.index]
      const from = page.style.transform
      page.style.transform = ""
      if (!prefersReducedMotion()) {
        page.animate([ { transform: from }, { transform: "none" } ], { duration: 420, easing: "cubic-bezier(.2,.9,.3,1.2)" })
      }
      return
    }

    if (!this.turn) return
    // Speed over the last ~50 ms, signed towards the turn: a flick back at the end cancels the turn.
    const recent = g.samples.find(([ , t ]) => e.timeStamp - t < 50) || g.samples.at(-2) || g.samples[0]
    const speed = (e.clientX - recent[0]) / Math.max(1, e.timeStamp - recent[1])
    const toward = g.forward ? -speed : speed
    const commit = !cancelled && toward > -FLICK_SPEED && (this.turn.p > COMMIT_DISTANCE || toward > FLICK_SPEED)
    this.animateTo(commit ? 1 : 0)
  }

  tap(e) {
    if (e.defaultPrevented || e.detail === 0) return // detail 0: a click synthesised from the keyboard
    const owner = e.target.closest(this.tapIgnore)
    if (owner && owner !== this.viewport && this.viewport.contains(owner)) return
    if (!this.canTap(e)) return

    const rect = this.viewport.getBoundingClientRect()
    const x = (e.clientX - rect.left) / rect.width
    if (x < TAP_ZONE) this.previous()
    else if (x > 1 - TAP_ZONE) this.next()
    else this.onCenterTap?.(e)
  }
}
