import { h } from "reader/dom"
import { tokenizedText } from "reader/text"

// Panels stacked vertically; bubbles are HTML laid over the image at box {x,y,w,h} (percent).
// Font size follows the panel width via container query units (see .wt-bubble).
export function renderWebtoon(stage, episode, t) {
  const fragment = document.createDocumentFragment()

  for (const panel of episode.panels) {
    const figure = h("figure", { class: "wt-panel", "data-position": panel.position,
                                 style: `aspect-ratio: ${panel.aspect_ratio}` })
    if (panel.image_url) {
      figure.append(h("img", { src: panel.image_url, alt: "", decoding: "async",
                               loading: panel.position < 2 ? "eager" : "lazy" }))
    }

    const loose = []
    for (const bubble of panel.bubbles) {
      if (!bubble.box) { loose.push(bubble); continue }
      const { x, y, w, h: height } = bubble.box
      figure.append(h("div", { class: `wt-bubble wt-bubble--${bubble.kind}`, "data-bubble-id": bubble.id,
                               style: `left:${x}%;top:${y}%;width:${w}%;min-height:${height}%` },
        tokenizedText(bubble),
        translateButton(bubble, t)))
    }
    fragment.append(figure)

    // Bubbles without a box (should not happen for webtoon) are shown as a caption under the panel.
    for (const bubble of loose) {
      fragment.append(h("div", { class: "wt-caption", "data-bubble-id": bubble.id }, tokenizedText(bubble)))
    }
  }

  fragment.append(h("div", { class: "reader-end", "data-reader-end": "", style: "height:1px" }))
  stage.replaceChildren(fragment)
  return [ ...stage.querySelectorAll(".wt-panel") ]
}

function translateButton(bubble, t) {
  return h("button", { type: "button", class: "bubble-translate", "data-translate-bubble": bubble.id,
                       "aria-label": t.translate_phrase, title: t.translate_phrase }, "⇄")
}
