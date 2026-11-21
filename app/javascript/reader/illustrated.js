import { h } from "reader/dom"
import { tokenizedText } from "reader/text"
import { panelImage } from "reader/media"

// A short illustrated book: each panel is a section with an optional picture and paragraphs.
// Narration is a paragraph, dialogue lines carry the speaker's name.
export function renderIllustrated(stage, episode, t) {
  const characters = new Map(episode.characters.map((c) => [ c.id, c ]))
  const article = h("article", { class: "ill" })

  for (const panel of episode.panels) {
    const section = h("section", { class: "ill-section", "data-position": panel.position })
    const image = panelImage(panel, { eager: panel.position === 0 })
    if (image) section.append(h("figure", { class: "ill-figure", style: `aspect-ratio: ${panel.aspect_ratio}` }, image))

    for (const bubble of panel.bubbles) {
      const speaker = characters.get(bubble.character_id)
      const paragraph = h("div", { class: `ill-p ill-p--${bubble.kind}`, "data-bubble-id": bubble.id },
        bubble.kind !== "narration" && speaker ? h("span", { class: "ill-speaker" }, speaker.name) : null,
        tokenizedText(bubble, { tag: "span", className: "story-text" }),
        bubble.audio_url ? h("button", { type: "button", class: "ill-action", "data-speak-bubble": bubble.id,
                                         "aria-label": t.listen, title: t.listen }, "🔊") : null,
        h("button", { type: "button", class: "ill-action", "data-translate-bubble": bubble.id,
                      "aria-label": t.translate_phrase, title: t.translate_phrase }, "⇄"))
      section.append(paragraph)
    }
    article.append(section)
  }

  article.append(h("div", { class: "reader-end", "data-reader-end": "", style: "height:1px" }))
  stage.replaceChildren(article)
  return [ ...stage.querySelectorAll(".ill-section") ]
}
