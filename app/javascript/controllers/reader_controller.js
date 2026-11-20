import { Controller } from "@hotwired/stimulus"
import { h, prefersReducedMotion } from "reader/dom"
import { renderWebtoon } from "reader/webtoon"
import { renderChat } from "reader/chat"
import { WordSheet } from "reader/sheet"
import { renderSummary, updateSummary } from "reader/summary"
import { speak, stopSpeaking } from "reader/speech"
import { request } from "reader/api"
import { readPref, writePref } from "reader/prefs"

const THEME_COLORS = { light: "#fbf9f3", night: "#0e0e12" }

// The reader renders the whole interactive layer from the episode JSON embedded in the page
// (the same shape API v1 will serve). Tapping a word opens the sheet instantly; only saving
// words and progress talk to the server.
//
// Progress position: panel index for webtoon, index of the last revealed message for chat.
export default class extends Controller {
  static targets = [ "payload", "stage", "summary", "sheet", "progressBar", "settings", "settingsButton",
                     "romanizationToggle", "highlightToggle", "nightToggle" ]
  static values = { i18n: Object, progressUrl: String, saveUrl: String, reviewUrl: String, libraryUrl: String,
                    episodeUrl: String }

  connect() {
    this.episode = JSON.parse(this.payloadTarget.textContent)
    this.t = this.i18nValue
    this.lang = this.episode.language_pair.target_lang
    this.indexEpisode()

    this.saved = new Set(this.episode.user?.saved_lexeme_ids ?? [])
    this.furthest = this.episode.user?.last_panel_position ?? 0
    this.completed = this.episode.user?.completed ?? false

    this.sheet = new WordSheet(this.sheetTarget, this.t, {
      onSave: () => this.toggleSave(this.current?.lexeme.id, this.current?.token.id),
      onSpeak: () => this.speakCurrent(),
      onClose: () => this.clearActive()
    })
    this.loadPrefs()

    if (this.episode.format === "chat") this.setupChat()
    else this.setupWebtoon() // manga and illustrated get their own layouts in wave 5

    this.paintSaved()
    this.updateProgressBar()

    this.onDocumentClick = (event) => this.documentClick(event)
    this.onKeydown = (event) => { if (event.key === "Escape") this.sheet.close() }
    this.onPageHide = () => this.flushProgress()
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("pagehide", this.onPageHide)

    this.dispatch("started", { detail: this.eventDetail() })
  }

  disconnect() {
    this.observer?.disconnect()
    this.endObserver?.disconnect()
    this.nextBar?.remove()
    this.flushProgress()
    stopSpeaking()
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("pagehide", this.onPageHide)
    this.setTheme(false) // other pages use the light theme
  }

  // ── Webtoon ──────────────────────────────────────────────

  setupWebtoon() {
    const panels = renderWebtoon(this.stageTarget, this.episode, this.t)
    this.total = panels.length

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
      requestAnimationFrame(() => panels[this.furthest]?.scrollIntoView({ block: "start" }))
    }
  }

  // ── Chat ─────────────────────────────────────────────────

  setupChat() {
    this.items = renderChat(this.stageTarget, this.episode, this.t)
    this.total = this.items.length
    this.nextBar = h("div", { class: "chat-next-bar" },
      h("button", { type: "button", class: "reader-btn", "data-action": "reader#revealNext" }, `${this.t.next_message} ↓`))
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
    const translate = event.target.closest("[data-translate-bubble]")
    const token = event.target.closest("[data-token-id]")
    const bubble = event.target.closest("[data-bubble-id]")

    if (translate) this.openPhrase(Number(translate.dataset.translateBubble))
    else if (token) this.openToken(token)
    else if (bubble) this.openPhrase(Number(bubble.dataset.bubbleId)) // tap on the bubble outside words
    else return

    event.stopPropagation() // keep the document handler from closing the sheet we just opened
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
    if (!this.sheet.isOpen) return
    if (this.sheetTarget.contains(event.target)) return
    this.sheet.close()
  }

  openToken(element) {
    const token = this.tokens.get(Number(element.dataset.tokenId))
    const lexeme = this.lexeme(token.lexeme_id)
    this.current = { token, lexeme }
    this.setActive(element)
    this.sheet.showToken({ token, lexeme, saved: this.saved.has(lexeme.id), lang: this.lang })
    this.dispatch("token-tapped", { detail: { ...this.eventDetail(), tokenId: token.id, lexemeId: lexeme.id } })
  }

  openPhrase(bubbleId) {
    const bubble = this.bubbles.get(bubbleId)
    this.current = null
    this.currentBubble = bubble
    this.clearActive()
    this.sheet.showPhrase({ bubble, lang: this.lang })
    this.dispatch("bubble-translated", { detail: { ...this.eventDetail(), bubbleId } })
  }

  speakCurrent() {
    if (this.current) speak(this.current.token.surface, this.lang, null)
    else if (this.currentBubble) speak(this.currentBubble.text, this.lang, this.currentBubble.audio_url)
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

  toggleSettings() {
    const open = this.settingsTarget.hidden
    this.settingsTarget.hidden = !open
    this.settingsButtonTarget.setAttribute("aria-expanded", String(open))
  }

  loadPrefs() {
    this.prefs = {
      romanization: readPref("romanization", false),
      highlight: readPref("highlight", true),
      night: readPref("night", false)
    }
    if (this.hasRomanizationToggleTarget) this.romanizationToggleTarget.checked = this.prefs.romanization
    this.highlightToggleTarget.checked = this.prefs.highlight
    this.nightToggleTarget.checked = this.prefs.night
    this.applyPrefs()
  }

  setPref(event) {
    const name = event.target.dataset.pref
    this.prefs[name] = event.target.checked
    writePref(name, event.target.checked)
    this.applyPrefs()
  }

  applyPrefs() {
    this.element.dataset.romanization = this.prefs.romanization ? "on" : "off"
    this.element.dataset.highlight = this.prefs.highlight ? "on" : "off"
    this.setTheme(this.prefs.night)
  }

  setTheme(night) {
    const root = document.documentElement
    if (night) root.dataset.theme = "night"
    else delete root.dataset.theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", night ? THEME_COLORS.night : THEME_COLORS.light)
  }

  // ── Helpers ──────────────────────────────────────────────

  indexEpisode() {
    this.tokens = new Map()
    this.bubbles = new Map()
    for (const panel of this.episode.panels) {
      for (const bubble of panel.bubbles) {
        this.bubbles.set(bubble.id, bubble)
        for (const token of bubble.tokens) this.tokens.set(token.id, token)
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
