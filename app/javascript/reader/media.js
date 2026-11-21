import { h } from "reader/dom"
import { icon } from "reader/icons"

// Panel image with WebP srcset (800w / 1200w); `sizes` says how wide it is drawn.
export function panelImage(panel, { sizes = "(max-width: 640px) 100vw, 640px", eager = false } = {}) {
  if (!panel.image_url) return null
  return h("img", { src: panel.image_url, srcset: panel.image_srcset || null, sizes, alt: "", decoding: "async",
                    loading: eager ? "eager" : "lazy" })
}

// Small round buttons in the bubble corner: translate always, listen when the line has recorded audio.
export function bubbleButtons(bubble, t) {
  return [
    bubble.audio_url ? h("button", { type: "button", class: "bubble-audio", "data-speak-bubble": bubble.id,
                                     "aria-label": t.listen, title: t.listen }, icon("sound")) : null,
    h("button", { type: "button", class: "bubble-translate", "data-translate-bubble": bubble.id,
                  "aria-label": t.translate_phrase, title: t.translate_phrase }, icon("translate"))
  ]
}
