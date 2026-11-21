import { h } from "reader/dom"
import { tokenizedText } from "reader/text"
import { panelImage, bubbleButtons } from "reader/media"

// Panels stacked vertically; bubbles are HTML laid over the image at box {x,y,w,h} (percent).
// Font size follows the panel width via container query units (see .wt-bubble).
export function renderWebtoon(stage, episode, t) {
  const fragment = document.createDocumentFragment()

  for (const panel of episode.panels) {
    const figure = h("figure", { class: "wt-panel", "data-position": panel.position,
                                 style: `aspect-ratio: ${panel.aspect_ratio}` })
    const loose = appendPanel(figure, panel, t, { eager: panel.position < 2 })
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

// Image plus bubbles laid over it; returns bubbles without a box (shown as captions by the caller).
export function appendPanel(figure, panel, t, { sizes, eager = false } = {}) {
  figure.append(panelImage(panel, { sizes, eager }) || "")
  const loose = []
  for (const bubble of panel.bubbles) {
    if (!bubble.box) { loose.push(bubble); continue }
    const { x, y, w, h: height } = bubble.box
    figure.append(h("div", { class: `wt-bubble wt-bubble--${bubble.kind}`, "data-bubble-id": bubble.id,
                             style: `left:${x}%;top:${y}%;width:${w}%;min-height:${height}%` },
      tokenizedText(bubble),
      bubbleButtons(bubble, t)))
  }
  return loose
}

// Boxes come from the generator in percent, but text height depends on the screen and font.
// If a bubble spills over the panel edge, slide it back inside (never resize the text).
export function fitBubbles(root) {
  for (const figure of root.querySelectorAll(".wt-panel")) {
    const width = figure.clientWidth
    const height = figure.clientHeight
    for (const bubble of figure.querySelectorAll(".wt-bubble")) {
      bubble.style.translate = ""
      const overflowY = bubble.offsetTop + bubble.offsetHeight - (height - 4)
      const overflowX = bubble.offsetLeft + bubble.offsetWidth - (width - 4)
      const dy = overflowY > 0 ? -Math.min(overflowY, bubble.offsetTop - 4) : 0
      const dx = overflowX > 0 ? -Math.min(overflowX, bubble.offsetLeft - 4) : 0
      if (dx || dy) bubble.style.translate = `${dx}px ${dy}px`
    }
  }
}
