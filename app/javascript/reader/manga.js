import { h } from "reader/dom"
import { appendPanel } from "reader/webtoon"

const AUTO_PANELS_PER_PAGE = 3

// One page at a time: the controller hands the pages to reader/pager.js (swipe and tap the edges on
// phones, arrows and keys everywhere). Each page is a 2-column grid: cols 2 = full width, cols 1 = half width.
// Panels without layout.page are paginated automatically, so any webtoon can be shown as manga.
export function renderManga(stage, episode, t) {
  const pages = paginate(episode.panels)
  const pager = h("div", { class: "manga-pager", tabindex: "0", "aria-roledescription": "carousel" })

  pages.forEach((panels, index) => {
    const page = h("section", { class: "manga-page", "data-page": index, "data-last-position": panels.at(-1).position,
                                "aria-label": `${index + 1} / ${pages.length}` })
    for (const panel of panels) {
      const cols = panel.layout?.cols === 1 ? 1 : 2
      const figure = h("figure", { class: `wt-panel manga-panel manga-panel--${cols}`, "data-position": panel.position,
                                   style: `aspect-ratio: ${panel.aspect_ratio}` })
      appendPanel(figure, panel, t, { sizes: cols === 1 ? "(max-width: 640px) 50vw, 320px" : undefined, eager: index === 0 })
      page.append(figure)
    }
    pager.append(page)
  })

  const counter = h("span", { class: "manga-counter", "aria-live": "polite" }, `1 / ${pages.length}`)
  const nav = h("div", { class: "manga-nav" },
    h("button", { type: "button", class: "reader-btn reader-btn--ghost reader-btn--icon", "data-action": "reader#previousPage",
                  "aria-label": t.previous_page }, "‹"),
    counter,
    h("button", { type: "button", class: "reader-btn reader-btn--icon", "data-action": "reader#nextPage",
                  "aria-label": t.next_page }, "›"))

  stage.replaceChildren(pager, nav)
  return { pager, pages: [ ...pager.querySelectorAll(".manga-page") ], counter }
}

function paginate(panels) {
  if (panels.every((panel) => panel.layout?.page)) {
    const byPage = new Map()
    for (const panel of panels) {
      const page = panel.layout.page
      byPage.set(page, [ ...(byPage.get(page) || []), panel ])
    }
    return [ ...byPage.keys() ].sort((a, b) => a - b).map((page) => byPage.get(page))
  }
  const pages = []
  for (let i = 0; i < panels.length; i += AUTO_PANELS_PER_PAGE) pages.push(panels.slice(i, i + AUTO_PANELS_PER_PAGE))
  return pages
}
