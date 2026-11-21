// Per-device reader preferences. Storage can be unavailable (private mode), so every access is guarded.
const PREFIX = "storyloop:"

export function readPref(name, fallback) {
  try {
    const value = localStorage.getItem(PREFIX + name)
    return value === null ? fallback : value === "1"
  } catch {
    return fallback
  }
}

export function writePref(name, value) {
  try { localStorage.setItem(PREFIX + name, value ? "1" : "0") } catch {}
}

// A pref with a fixed set of values; anything else stored (an old or tampered value) reads as the fallback.
export function readChoice(name, choices, fallback) {
  try {
    const value = localStorage.getItem(PREFIX + name)
    return choices.includes(value) ? value : fallback
  } catch {
    return fallback
  }
}

export function writeChoice(name, value) {
  try { localStorage.setItem(PREFIX + name, value) } catch {}
}
