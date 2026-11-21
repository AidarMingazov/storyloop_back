// Icons from the page's sprite (app/views/shared/_icons.html.erb), the client twin of DesignHelper#icon.
// Decorative by default; pass `label` when the icon is the only content of something a screen reader announces.
const SVG = "http://www.w3.org/2000/svg"

export function icon(name, { label = null, className = "" } = {}) {
  const svg = document.createElementNS(SVG, "svg")
  svg.setAttribute("class", `icon ${className}`.trim())
  svg.setAttribute("viewBox", "0 0 24 24")
  if (label) {
    svg.setAttribute("role", "img")
    svg.setAttribute("aria-label", label)
  } else {
    svg.setAttribute("aria-hidden", "true")
  }
  const use = document.createElementNS(SVG, "use")
  use.setAttribute("href", `#i-${name}`)
  svg.append(use)
  return svg
}

// Swap the symbol in place. Replacing the <svg> would detach a node the user just clicked, and
// outside-click handlers would then take that click for one outside the sheet.
export function setIcon(svg, name) {
  svg?.querySelector("use")?.setAttribute("href", `#i-${name}`)
}
