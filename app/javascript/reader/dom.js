// Tiny element builder. Text children are appended as text nodes, so story content is never parsed as HTML.
export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue
    el.setAttribute(key, value === true ? "" : value)
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false || child === "") continue
    el.append(child)
  }
  return el
}

export const prefersReducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
