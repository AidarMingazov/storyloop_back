import { Controller } from "@hotwired/stimulus"
import { h, prefersReducedMotion } from "reader/dom"
import { renderWebtoon, fitBubbles } from "reader/webtoon"
import { renderChat } from "reader/chat"
import { renderManga } from "reader/manga"
import { Pager, PAGE_TURN_EFFECTS } from "reader/pager"
import { renderIllustrated } from "reader/illustrated"
import { WordCard } from "reader/word_card"
import { renderSummary, updateSummary } from "reader/summary"
import { speak, stopSpeaking } from "reader/speech"
import { request } from "reader/api"
import { readPref, writePref, readChoice, writeChoice } from "reader/prefs"
import { icon } from "reader/icons"

const THEME_COLORS = { light: "#fbf9f4", night: "#0e0f13" }
const THEMES = [ "auto", "light", "night" ]
const TEXT_SIZES = [ "s", "m", "l" ]
const onOff = (value) => value ? "on" : "off"

// The reader renders the whole interactive layer from the episode JSON embedded in the page
// (the same shape API v1 will serve). Tapping a word opens its card instantly; a tap on a line outside
// the words shows its translation in place; only saving words and progress talk to the server.
// The header hides while the reader scrolls down a webtoon or a book and comes back on the way up.
//
// Progress position: panel index for webtoon, manga and illustrated; index of the last revealed
// message for chat.
export default class extends Controller {
  static targets = [ "payload", "stage", "summary", "sheet", "progressBar", "header", "settings", "settingsButton",
                     "prefSwitch", "prefChoice" ]
  static values = { i18n: Object, progressUrl: String, saveUrl: String, reviewUrl: String, libraryUrl: String,
                    episodeUrl: String, signupUrl: String }

  connect() {
    this.episode = JSON.parse(this.payloadTarget.textContent)
    this.t = this.i18nValue
    this.lang = this.episode.language_pair.target_lang
    this.nativeLang = this.episode.language_pair.native_lang
    this.systemDark = window.matchMedia("(prefers-color-scheme: dark)")
    this.programmaticUntil = 0
    this.ownScrollTo = null
    this.indexEpisode()

    this.saved = new Set(this.episode.user?.saved_lexeme_ids ?? [])
    this.furthest = this.episode.user?.last_panel_position ?? 0
    this.completed = this.episode.user?.completed ?? false

    this.sheet = new WordCard(this.sheetTarget, this.t, {
      onSave: () => this.toggleSave(this.current?.lexeme.id, this.current?.token.id),
      onSpeak: () => this.speakCurrent(),
      onSpeakLine: () => this.speakLine(this.current?.bubble),
      onClose: () => this.cardClosed()
    })
    this.loadPrefs()

    switch (this.episode.format) {
      case "chat": this.setupChat(); break
      case "manga": this.setupManga(); break
      case "illustrated": this.setupScrolling(renderIllustrated(this.stageTarget, this.episode, this.t)); break
      default: this.setupScrolling(renderWebtoon(this.stageTarget, this.episode, this.t))
    }

    this.paintSaved()
    this.updateProgressBar()

    this.onResize = () => {
      fitBubbles(this.stageTarget)
      if (this.sheet.isPopover) this.sheet.close() // its word has moved
    }
    this.onResize()
    document.fonts?.ready.then(() => fitBubbles(this.stageTarget)) // not onResize: a late font must not close a card
    window.addEventListener("resize", this.onResize)

    this.onDocumentClick = (event) => this.documentClick(event)
    this.onKeydown = (event) => this.keydown(event)
    this.onPageHide = () => this.flushProgress()
    this.lastScrollY = window.scrollY
    this.onScroll = () => this.scrolled()
    this.onSystemTheme = () => this.applyTheme()
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.systemDark.addEventListener("change", this.onSystemTheme)
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("pagehide", this.onPageHide)

    this.dispatch("started", { detail: this.eventDetail() })
  }

  disconnect() {
    this.observer?.disconnect()
    this.endObserver?.disconnect()
    this.pager?.destroy()
    this.nextBar?.remove()
    this.flushProgress()
    stopSpeaking()
    window.removeEventListener("scroll", this.onScroll)
    this.systemDark.removeEventListener("change", this.onSystemTheme)
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("pagehide", this.onPageHide)
    this.paintTheme(false) // other pages use the light theme
  }

  // ── Webtoon and illustrated: vertical scrolling ──────────

  setupScrolling(panels) {
    this.total = panels.length
    this.autoHideChrome = true

    // A panel counts as read when it crosses the middle band of the screen.
    this.observer = new IntersectionObserver((entries) => {
      for (const entry of entries) if (entry.isIntersecting) this.reached(Number(entry.target.dataset.position))
    }, { rootMargin: "-45% 0px -45% 0px" })
    panels.forEach((panel) => this.observer.observe(panel))

    this.endObserver = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.complete()
    })
    this.endObserver.observe(this.stageTarget.querySelector("[data-reader-end]"))

    if (this.completed) {
      this.showSummary()
    } else if (this.furthest > 0) {
      requestAnimationFrame(() => {
        this.programmaticUntil = performance.now() + 300 // coming back to the place is not "scrolling on"
        panels[this.furthest]?.scrollIntoView({ block: "start" })
      })
    }
  }

  // ── Manga: one page per screen ───────────────────────────

  setupManga() {
    const { pager, pages, counter } = renderManga(this.stageTarget, this.episode, this.t)
    this.pages = pages
    this.pageCounter = counter
    this.total = this.episode.panels.length

    const resume = this.completed ? 0 : this.pages.findIndex((page) => Number(page.dataset.lastPosition) >= this.furthest)
    this.pager = new Pager(pager, pages, {
      index: Math.max(0, resume),
      effect: this.prefs.page_turn,
      tapIgnore: "[data-token-id], [data-bubble-id], [data-translate-bubble], [data-speak-bubble]",
      // With the word sheet open, a tap on the page only closes it.
      canTap: () => !this.sheet.isOpen && !this.settingsOpen,
      onTurnStart: () => this.sheet.close(),
      onReveal: (page) => fitBubbles(page),
      onChange: (index, previous) => this.pageChanged(index, previous)
    })

    if (this.completed) this.showSummary()
    this.pageChanged(this.pager.index)
  }

  nextPage() { this.pager?.next() }
  previousPage() { this.pager?.previous() }

  pageChanged(index, previous) {
    this.pageIndex = index
    this.updatePageCounter(previous === undefined ? 0 : Math.sign(index - previous))
    this.reached(Number(this.pages[index].dataset.lastPosition))
    if (index === this.pages.length - 1) this.complete()
    if (previous !== undefined && previous !== index) {
      try { navigator.vibrate?.(8) } catch {} // Android only; iOS haptics come with the native shell (wave S)
    }
  }

  // The new number rolls in from the side the reader is going.
  updatePageCounter(direction) {
    const value = h("span", { class: "manga-counter-value" }, `${this.pageIndex + 1} / ${this.pages.length}`)
    this.pageCounter.replaceChildren(value)
    if (!direction || prefersReducedMotion()) return
    value.animate([ { transform: `translateY(${direction * 70}%)`, opacity: 0 }, { transform: "none", opacity: 1 } ],
                  { duration: 260, easing: "cubic-bezier(.2,.8,.2,1)" })
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.closeSettings()
      return this.sheet.close()
    }
    if (event.target.closest("input, textarea, select") || event.metaKey || event.ctrlKey || event.altKey) return
    // With a word's card open: S saves it, L says it (key codes, so they work on any keyboard layout).
    if (this.sheet.isOpen && this.current) {
      if (event.code === "KeyS") return this.toggleSave(this.current.lexeme.id, this.current.token.id)
      if (event.code === "KeyL") return this.speakCurrent()
    }
    if (!this.pager) return
    if (event.key === "ArrowRight") { event.preventDefault(); this.nextPage() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previousPage() }
  }

  // ── Chat ─────────────────────────────────────────────────

  setupChat() {
    this.items = renderChat(this.stageTarget, this.episode, this.t)
    this.total = this.items.length
    this.nextBar = h("div", { class: "chat-next-bar" },
      h("button", { type: "button", class: "reader-btn", "data-action": "reader#revealNext" }, this.t.next_message, icon("arrow-down")))
    this.element.append(this.nextBar)

    this.revealed = this.completed ? this.total : Math.min(this.total, Math.max(1, this.furthest + 1))
    this.items.slice(0, this.revealed).forEach((item) => { item.hidden = false })
    if (this.revealed > 1) requestAnimationFrame(() => this.items[this.revealed - 1].scrollIntoView({ block: "end" }))

    if (this.revealed >= this.total) {
      this.nextBar.hidden = true
      this.completed ? this.showSummary() : this.complete()
    }
  }

  revealNext() {
    if (this.revealed >= this.total) return
    const item = this.items[this.revealed]
    item.hidden = false
    this.revealed += 1
    item.scrollIntoView({ behavior: prefersReducedMotion() ? "auto" : "smooth", block: "end" })
    this.reached(this.revealed - 1)

    if (this.revealed >= this.total) {
      this.nextBar.hidden = true
      this.complete()
    }
  }

  // ── Taps ─────────────────────────────────────────────────

  stageClick(event) {
    const listen = event.target.closest("[data-speak-bubble]")
    const translate = event.target.closest("[data-translate-bubble]")
    const token = event.target.closest("[data-token-id]")
    const bubble = event.target.closest("[data-bubble-id]")

    if (listen) this.speakLine(this.bubbles.get(Number(listen.dataset.speakBubble)))
    else if (token) this.openToken(token)
    else if (translate) this.toggleTranslation(Number(translate.dataset.translateBubble))
    // A tap on the line outside its words. With a card open it only closes the card (documentClick).
    else if (bubble && !this.sheet.isOpen && !this.settingsOpen) this.toggleTranslation(Number(bubble.dataset.bubbleId))
    else {
      // A tap on the picture shows or hides the header — unless it is closing a card or the settings.
      if (!bubble && this.autoHideChrome && !this.sheet.isOpen && !this.settingsOpen) this.showChrome(!this.chromeVisible)
      return
    }

    event.stopPropagation() // keep the document handler from closing the card we just opened
  }

  stageKeydown(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    const token = event.target.closest("[data-token-id]")
    if (!token) return
    event.preventDefault()
    event.stopPropagation()
    this.openToken(token)
  }

  documentClick(event) {
    const target = event.target
    if (!target.isConnected) return // re-rendered by our own click handler, so it was inside
    if (this.settingsOpen && !this.settingsTarget.contains(target) && !this.settingsButtonTarget.contains(target)) this.closeSettings()
    if (this.sheet.isOpen && !this.sheetTarget.contains(target)) this.sheet.close()
  }

  openToken(element) {
    const token = this.tokens.get(Number(element.dataset.tokenId))
    const lexeme = this.lexeme(token.lexeme_id)
    const bubble = this.tokenBubbles.get(token.id)
    this.closeSettings()
    this.current = { token, lexeme, bubble }
    this.setActive(element)
    this.sheet.show({ token, lexeme, bubble, saved: this.saved.has(lexeme.id), lang: this.lang, nativeLang: this.nativeLang }, element)
    this.keepLineVisible(element)
    this.dispatch("token-tapped", { detail: { ...this.eventDetail(), tokenId: token.id, lexemeId: lexeme.id } })
  }

  // On a phone the sheet covers the bottom of the screen: scroll just enough to keep the tapped line above it.
  keepLineVisible(element) {
    const covered = this.sheet.coveredHeight
    this.element.style.setProperty("--sheet-space", `${covered}px`) // room to bring the last lines above the sheet
    this.sheetOpenedAt = window.scrollY
    if (!covered) return

    const line = (element.closest("[data-bubble-id]") || element).getBoundingClientRect()
    const top = (this.chromeVisible ? this.headerTarget.offsetHeight : 0) + 8
    const bottom = window.innerHeight - covered - 12
    let delta = 0
    if (line.bottom > bottom) delta = Math.min(line.bottom - bottom, line.top - top)
    else if (line.top < top) delta = line.top - top
    if (Math.abs(delta) < 2) return

    this.sheetOpenedAt += delta
    this.ownScrollTo = this.sheetOpenedAt               // in flight until the page gets there…
    this.programmaticUntil = performance.now() + 1500   // …or we stop waiting (the reader took over, a slow device)
    window.scrollBy({ top: delta, behavior: prefersReducedMotion() ? "auto" : "smooth" })
  }

  cardClosed() {
    this.clearActive()
    this.ownScrollTo = null
    this.element.style.removeProperty("--sheet-space")
  }

  // The line's translation, shown inside its bubble (see lineTranslation in reader/media.js).
  toggleTranslation(bubbleId) {
    const element = this.stageTarget.querySelector(`[data-bubble-id="${bubbleId}"]`)
    if (!element?.querySelector(".bubble-tr")) return

    const shown = element.classList.toggle("is-translated")
    element.querySelector("[data-translate-bubble]")?.setAttribute("aria-expanded", String(shown))
    fitBubbles(this.stageTarget) // the bubble grew or shrank
    if (shown) this.dispatch("bubble-translated", { detail: { ...this.eventDetail(), bubbleId } })
  }

  speakCurrent() {
    // Recorded audio of the dictionary form when we have it, otherwise the word as written.
    if (this.current) speak(this.current.token.surface, this.lang, this.current.lexeme.audio_url)
  }

  speakLine(bubble) {
    if (bubble) speak(bubble.text, this.lang, bubble.audio_url)
  }

  // ── Header ───────────────────────────────────────────────

  get chromeVisible() {
    return !this.element.classList.contains("chrome-off")
  }

  showChrome(visible) {
    this.element.classList.toggle("chrome-off", !visible)
  }

  revealChrome() { this.showChrome(true) } // keyboard focus moved into the hidden header

  scrolled() {
    const y = window.scrollY
    const delta = y - this.lastScrollY
    this.lastScrollY = y
    // Our own scrolls (coming back to the place, keeping a line above the sheet) are not the reader scrolling on.
    if (this.ownScrollTo != null && Math.abs(y - this.ownScrollTo) < 2) { // arrived
      this.ownScrollTo = null
      this.programmaticUntil = 0
      return
    }
    if (performance.now() < this.programmaticUntil) return
    if (this.ownScrollTo != null) { // never arrived: measure "scrolled on" from here
      this.ownScrollTo = null
      this.sheetOpenedAt = y
    }

    if (this.autoHideChrome && !this.settingsOpen) {
      if (delta > 6 && y > 120) this.showChrome(false)
      else if (delta < -6 || y < 60) this.showChrome(true)
    }
    // Scrolling on with the sheet open means the reader moved on: get the sheet out of the way.
    // A popover stays: it scrolls with its word.
    if (this.sheet.isOpen && !this.sheet.isPopover && Math.abs(y - this.sheetOpenedAt) > 160) this.sheet.close()
  }

  setActive(element) {
    this.clearActive()
    element.classList.add("is-active")
    this.activeElement = element
  }

  clearActive() {
    this.activeElement?.classList.remove("is-active")
    this.activeElement = null
  }

  // ── Saving words ─────────────────────────────────────────

  saveFromSummary(event) {
    const button = event.currentTarget
    this.toggleSave(Number(button.dataset.lexemeId), Number(button.dataset.tokenId))
  }

  async toggleSave(lexemeId, tokenId) {
    if (!lexemeId) return
    const wasSaved = this.saved.has(lexemeId)
    this.applySaved(lexemeId, !wasSaved) // optimistic

    try {
      if (wasSaved) {
        await request("DELETE", `${this.saveUrlValue}/${lexemeId}`)
      } else {
        await request("POST", this.saveUrlValue, { lexeme_id: lexemeId, token_id: tokenId })
        this.dispatch("word-saved", { detail: { ...this.eventDetail(), lexemeId, tokenId } })
      }
    } catch {
      this.applySaved(lexemeId, wasSaved)
      this.sheet.showError(this.t.save_failed)
    }
  }

  applySaved(lexemeId, saved) {
    saved ? this.saved.add(lexemeId) : this.saved.delete(lexemeId)
    for (const element of this.stageTarget.querySelectorAll(`[data-lexeme-id="${lexemeId}"]`)) {
      element.classList.toggle("is-saved", saved)
    }
    if (this.current?.lexeme.id === lexemeId) this.sheet.setSaved(saved)
    if (!this.summaryTarget.hidden) {
      updateSummary(this.summaryTarget, { saved: this.saved, savedInEpisode: this.savedInEpisode(), t: this.t })
    }
  }

  paintSaved() {
    for (const element of this.stageTarget.querySelectorAll("[data-lexeme-id]")) {
      element.classList.toggle("is-saved", this.saved.has(Number(element.dataset.lexemeId)))
    }
  }

  savedInEpisode() {
    return Object.keys(this.episode.lexemes).filter((id) => this.saved.has(Number(id))).length
  }

  // ── Progress and summary ─────────────────────────────────

  reached(position) {
    if (position <= this.furthest) return
    this.furthest = position
    this.updateProgressBar()
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.saveProgress(), 1200)
  }

  complete() {
    if (this.completed) return
    this.completed = true
    this.furthest = Math.max(this.furthest, this.total - 1)
    this.updateProgressBar()
    this.saveProgress()
    this.sheet.close()
    this.showSummary()
    this.dispatch("completed", { detail: this.eventDetail() })
  }

  saveProgress() {
    clearTimeout(this.saveTimer)
    this.saveTimer = null
    request("PATCH", this.progressUrlValue, { last_panel_position: this.furthest, completed: this.completed },
            { keepalive: true }).catch(() => {})
  }

  flushProgress() {
    if (this.saveTimer) this.saveProgress()
  }

  updateProgressBar() {
    const done = this.completed ? this.total : this.furthest + 1
    this.progressBarTarget.style.width = `${this.total ? Math.min(100, (done / this.total) * 100) : 0}%`
  }

  showSummary() {
    renderSummary(this.summaryTarget, {
      t: this.t, lang: this.lang, saved: this.saved, savedInEpisode: this.savedInEpisode(),
      words: this.targetWords(), reviewUrl: this.reviewUrlValue, libraryUrl: this.libraryUrlValue,
      signupUrl: this.episode.user?.guest ? this.signupUrlValue : null,
      next: this.episode.next_episode && {
        url: this.episodeUrlValue.replace("__ID__", this.episode.next_episode.id),
        locked: this.episode.next_episode.locked
      }
    })
    this.summaryTarget.hidden = false
  }

  // Target words of the episode matched to its tokens (by lemma, then by surface).
  targetWords() {
    const tokens = [ ...this.tokens.values() ]
    const seen = new Set()
    const words = []
    for (const word of this.episode.target_words) {
      const needle = word.toLowerCase()
      const token = tokens.find((tk) => this.lexeme(tk.lexeme_id).lemma.toLowerCase() === needle) ||
                    tokens.find((tk) => tk.surface.toLowerCase() === needle)
      if (!token || seen.has(token.lexeme_id)) continue
      seen.add(token.lexeme_id)
      words.push({ lexeme: this.lexeme(token.lexeme_id), token })
    }
    return words
  }

  // ── Settings ─────────────────────────────────────────────

  // The settings are a bottom sheet opened from the language pill; like the word card it does not dim the page.

  get settingsOpen() {
    return this.settingsTarget.classList.contains("is-open")
  }

  toggleSettings() {
    this.settingsOpen ? this.closeSettings() : this.openSettings()
  }

  openSettings() {
    this.sheet.close()
    this.showChrome(true)
    this.setSettingsOpen(true)
    this.settingsTarget.focus({ preventScroll: true })
  }

  closeSettings() {
    if (!this.settingsOpen) return
    const hadFocus = this.settingsTarget.contains(document.activeElement)
    this.setSettingsOpen(false)
    if (hadFocus) this.settingsButtonTarget.focus({ preventScroll: true })
  }

  setSettingsOpen(open) {
    this.settingsTarget.classList.toggle("is-open", open)
    this.settingsTarget.inert = !open
    this.settingsTarget.setAttribute("aria-hidden", String(!open))
    this.settingsButtonTarget.setAttribute("aria-expanded", String(open))
  }

  // Prefs live on the device. Switches are booleans, choices take one value of a fixed set;
  // the key in this.prefs is the storage key and the control's data-pref.
  loadPrefs() {
    const legacyNight = readPref("night", null) // before wave Р2 the theme was a night-mode switch
    this.prefs = {
      romanization: readPref("romanization", false),
      highlight: readPref("highlight", true),
      translations: readPref("translations", false),
      theme: readChoice("theme", THEMES, legacyNight === null ? "auto" : legacyNight ? "night" : "light"),
      size: readChoice("size", TEXT_SIZES, "m"),
      page_turn: readChoice("page_turn", PAGE_TURN_EFFECTS, "slide")
    }
    this.applyPrefs()
  }

  togglePref(event) {
    const name = event.currentTarget.dataset.pref
    this.prefs[name] = !this.prefs[name]
    writePref(name, this.prefs[name])
    this.applyPrefs()
  }

  choosePref(event) {
    const { pref, value } = event.currentTarget.dataset
    this.prefs[pref] = value
    writeChoice(pref, value)
    if (pref === "page_turn") this.pager?.setEffect(value)
    this.applyPrefs()
  }

  applyPrefs() {
    const { romanization, highlight, translations, size } = this.prefs
    Object.assign(this.element.dataset, { romanization: onOff(romanization), highlight: onOff(highlight),
                                          translations: onOff(translations), size })
    for (const control of this.prefSwitchTargets) control.setAttribute("aria-checked", String(Boolean(this.prefs[control.dataset.pref])))
    for (const control of this.prefChoiceTargets) {
      control.setAttribute("aria-pressed", String(this.prefs[control.dataset.pref] === control.dataset.value))
    }
    this.applyTheme()
    fitBubbles(this.stageTarget) // text size, romanization and translations change the bubbles' height
  }

  // "auto" follows the system; the layout's inline script does the same before first paint.
  applyTheme() {
    this.paintTheme(this.prefs.theme === "night" || (this.prefs.theme === "auto" && this.systemDark.matches))
  }

  paintTheme(night) {
    const root = document.documentElement
    if (night) root.dataset.theme = "night"
    else delete root.dataset.theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", night ? THEME_COLORS.night : THEME_COLORS.light)
  }

  // ── Helpers ──────────────────────────────────────────────

  indexEpisode() {
    this.tokens = new Map()
    this.bubbles = new Map()
    this.tokenBubbles = new Map() // token id → its line
    for (const panel of this.episode.panels) {
      for (const bubble of panel.bubbles) {
        this.bubbles.set(bubble.id, bubble)
        for (const token of bubble.tokens) {
          this.tokens.set(token.id, token)
          this.tokenBubbles.set(token.id, bubble)
        }
      }
    }
  }

  lexeme(id) {
    return this.episode.lexemes[id]
  }

  eventDetail() {
    return { episodeId: this.episode.id, format: this.episode.format, number: this.episode.number,
             pair: this.episode.language_pair.code, level: this.episode.cefr_level }
  }
}
