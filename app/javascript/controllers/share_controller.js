import { Controller } from "@hotwired/stimulus"

// "Share": the system share sheet where the browser has one (phones), otherwise copy the link.
// The link carries the sharer's ref and utm_medium = web_share | copy; the server logs story_shared.
export default class extends Controller {
  static values = { url: String, title: String, text: String, trackUrl: String, copied: String }

  async share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: this.titleValue, text: this.textValue, url: this.link("web_share") })
        this.track("web_share")
      } catch (error) {
        if (error.name !== "AbortError") this.copy()
      }
    } else {
      this.copy()
    }
  }

  async copy() {
    const url = this.link("copy")
    let copied = true
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      copied = false // no clipboard permission: show the link so it can be copied by hand
    }
    this.toast(copied ? this.copiedValue : url)
    this.track("copy")
  }

  link(medium) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("utm_medium", medium)
    return url.toString()
  }

  track(channel) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch(this.trackUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token, Accept: "application/json" },
      body: JSON.stringify({ channel })
    }).catch(() => {})
  }

  toast(text) {
    document.querySelector("[data-share-toast]")?.remove()
    const toast = document.createElement("div")
    toast.dataset.shareToast = ""
    toast.setAttribute("role", "status")
    toast.className = "fixed inset-x-4 bottom-6 z-50 mx-auto max-w-sm break-all rounded-xl bg-ink-strong px-4 py-3 text-center text-sm text-white shadow-lg"
    toast.textContent = text
    document.body.append(toast)
    setTimeout(() => toast.remove(), 4000)
  }
}
