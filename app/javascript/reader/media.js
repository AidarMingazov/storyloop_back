import { h } from "reader/dom"
import { icon } from "reader/icons"
import { canSpeak } from "reader/speech"

// Panel image with WebP srcset (800w / 1200w); `sizes` says how wide it is drawn.
export function panelImage(panel, { sizes = "(max-width: 640px) 100vw, 640px", eager = false } = {}) {
  if (!panel.image_url) return null
  return h("img", { src: panel.image_url, srcset: panel.image_srcset || null, sizes, alt: "", decoding: "async",
                    loading: eager ? "eager" : "lazy" })
}

// The line's translation with a play button, inside the bubble under its text. Hidden until the reader taps
// the bubble outside the words (or turns on "translation under every line"), so nothing sits over the art.
export function lineTranslation(bubble, t, nativeLang) {
  const playable = bubble.audio_url || canSpeak()
  if (!bubble.translation && !playable) return null
  return h("span", { class: "bubble-tr" },
    playable ? h("button", { type: "button", class: "bubble-play", "data-speak-bubble": bubble.id,
                             "aria-label": t.listen, title: t.listen }, icon("play")) : null,
    bubble.translation ? h("span", { class: "bubble-tr-text", lang: nativeLang }, bubble.translation) : null)
}
