import { Controller } from "@hotwired/stimulus"

// Theme is stored per-device in localStorage (NOT in the user profile), so each
// device keeps its own last-used mode across navigations. The inline script in
// the layout <head> applies the same value before first paint to avoid a flash.
const STORAGE_KEY = "theme"
const THEMES = ["system", "light", "dark"]
const THEME_LABELS = { system: "System", light: "Light", dark: "Dark" }

export default class extends Controller {
  connect() {
    this.applyTheme()

    // Re-apply when the OS preference changes (only matters in "system" mode)
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.systemListener = () => this.applyTheme()
    this.mediaQuery.addEventListener("change", this.systemListener)
  }

  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener("change", this.systemListener)
    }
  }

  get theme() {
    let stored
    try { stored = localStorage.getItem(STORAGE_KEY) } catch (_) { /* private mode */ }
    return THEMES.includes(stored) ? stored : "system"
  }

  set theme(value) {
    try { localStorage.setItem(STORAGE_KEY, value) } catch (_) { /* private mode */ }
  }

  toggle() {
    // Cycle through: system -> light -> dark -> system
    const nextIndex = (THEMES.indexOf(this.theme) + 1) % THEMES.length
    this.theme = THEMES[nextIndex]
    this.applyTheme()
  }

  setLight() {
    this.theme = "light"
    this.applyTheme()
  }

  setDark() {
    this.theme = "dark"
    this.applyTheme()
  }

  setSystem() {
    this.theme = "system"
    this.applyTheme()
  }

  applyTheme() {
    const mode = this.theme
    const isDark = mode === "dark" ||
      (mode === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches)

    document.documentElement.classList.toggle("dark", isDark)

    // Which icon is visible is pure CSS, keyed off this attribute — the same
    // attribute the pre-paint script in the layout <head> sets, so the icon is
    // already correct before this controller connects.
    document.documentElement.setAttribute("data-theme-mode", mode)

    this.updateLabels(mode)
  }

  updateLabels(mode) {
    // Every toggle on the page (desktop + mobile nav) shares the state, so keep
    // their tooltips in sync when one of them is clicked.
    const label = THEME_LABELS[mode] || THEME_LABELS.system
    const next = THEMES[(THEMES.indexOf(mode) + 1) % THEMES.length]
    const title = `Theme: ${label} (click for ${THEME_LABELS[next]})`

    document.querySelectorAll("[data-theme-target='button']").forEach((el) => {
      el.setAttribute("title", title)
      el.setAttribute("aria-label", title)
    })
  }
}
