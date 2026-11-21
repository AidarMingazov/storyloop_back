import { h } from "reader/dom"
import { tokenizedText } from "reader/text"
import { icon } from "reader/icons"

const AVATAR_COLORS = [ "#c4703f", "#3f74c4", "#7a64b8", "#3f8f62", "#b5527a", "#8a7a3a" ]

// Messenger layout: the protagonist on the right, everyone else on the left with an avatar.
// Every message starts hidden; the reader reveals them one by one.
export function renderChat(stage, episode, t) {
  const characters = new Map(episode.characters.map((c) => [ c.id, c ]))
  const list = h("div", { class: "chat" })
  const items = []
  let previousSender = null

  for (const panel of episode.panels) {
    if (panel.image_url) {
      items.push(h("div", { class: "chat-msg chat-msg--them" },
        h("img", { class: "chat-image", src: panel.image_url, srcset: panel.image_srcset || null,
                   sizes: "70vw", alt: "", loading: "lazy" })))
    }

    for (const bubble of panel.bubbles) {
      const character = characters.get(bubble.character_id)
      let item

      if (!character || bubble.kind === "narration") {
        item = h("div", { class: "chat-msg chat-msg--narration", "data-bubble-id": bubble.id }, tokenizedText(bubble))
        previousSender = null
      } else {
        const me = character.protagonist
        const firstInGroup = previousSender !== character.id
        const avatar = me ? null : h("span", {
          class: `chat-avatar ${firstInGroup ? "" : "chat-avatar--hidden"}`, "aria-hidden": "true",
          style: `--avatar-bg: ${avatarColor(character.key)}`
        }, character.name.slice(0, 1))

        item = h("div", { class: `chat-msg ${me ? "chat-msg--me" : "chat-msg--them"}` },
          avatar,
          h("div", { class: "min-w-0" },
            !me && firstInGroup ? h("p", { class: "chat-name" }, character.name) : null,
            h("div", { class: "chat-bubble", "data-bubble-id": bubble.id }, tokenizedText(bubble))),
          h("div", { class: "chat-actions" },
            bubble.audio_url ? h("button", { type: "button", class: "chat-translate", "data-speak-bubble": bubble.id,
                                             "aria-label": t.listen, title: t.listen }, icon("sound")) : null,
            h("button", { type: "button", class: "chat-translate", "data-translate-bubble": bubble.id,
                          "aria-label": t.translate_phrase, title: t.translate_phrase }, icon("translate"))))
        previousSender = character.id
      }
      items.push(item)
    }
  }

  for (const item of items) { item.hidden = true; list.append(item) }
  stage.replaceChildren(list)
  return items
}

function avatarColor(key) {
  const sum = Array.from(key).reduce((acc, ch) => acc + ch.codePointAt(0), 0)
  return AVATAR_COLORS[sum % AVATAR_COLORS.length]
}
