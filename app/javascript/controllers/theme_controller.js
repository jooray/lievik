import { Controller } from "@hotwired/stimulus"

// Theme is stored per-device in localStorage (NOT in the user profile), so each
// device keeps its own last-used mode across navigations. The inline script in
// the layout <head> applies the same value before first paint to avoid a flash.
const STORAGE_KEY = "theme"
const THEMES = ["system", "light", "dark"]

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
    const isDark = this.theme === "dark" ||
      (this.theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches)

    document.documentElement.classList.toggle("dark", isDark)

    // Update icon visibility
    this.updateIcons(isDark)
  }

  updateIcons(isDark) {
    // Update every theme toggle on the page (desktop + mobile nav) so they stay
    // in sync when one is toggled.
    document.querySelectorAll("[data-theme-icon='sun']").forEach((el) => el.classList.toggle("hidden", isDark))
    document.querySelectorAll("[data-theme-icon='moon']").forEach((el) => el.classList.toggle("hidden", !isDark))
  }
}
