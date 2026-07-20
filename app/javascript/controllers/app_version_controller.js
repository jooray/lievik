import { Controller } from "@hotwired/stimulus"

// Keeps an open tab (or an installed PWA, which may live for days) from running
// stale JS/CSS after a deploy. Polls /version.json and reloads when the build
// identity changes, showing a brief notice first so the reload isn't startling.
export default class extends Controller {
  static values = {
    current: String,
    url: String,
    interval: { type: Number, default: 120000 }
  }

  connect() {
    this.reloading = false
    this.failures = 0

    this.registerServiceWorker()
    this.timer = setInterval(() => this.check(), this.intervalValue)

    // A tab that has been backgrounded for hours is the most likely to be
    // stale, so check the moment it comes back.
    this.onVisible = () => {
      if (document.visibilityState === "visible") this.check()
    }
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  async registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return

    try {
      const registration = await navigator.serviceWorker.register("/service_worker.js", { scope: "/" })
      // A worker found waiting means a newer build is already downloaded.
      registration.addEventListener("updatefound", () => this.check())
    } catch (error) {
      console.warn("Service worker registration failed:", error)
    }
  }

  async check() {
    if (this.reloading || document.visibilityState !== "visible") return

    try {
      const response = await fetch(this.urlValue, {
        cache: "no-store",
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return

      const { version } = await response.json()
      this.failures = 0

      if (version && this.currentValue && version !== this.currentValue) {
        this.reload()
      }
    } catch (error) {
      // Offline or a blip — stop nagging the network after repeated failures.
      if (++this.failures >= 5) clearInterval(this.timer)
    }
  }

  async reload() {
    this.reloading = true
    clearInterval(this.timer)
    this.showNotice()

    // Let the worker hand over so the reload comes from the network.
    try {
      const registration = await navigator.serviceWorker?.getRegistration()
      registration?.waiting?.postMessage("skip-waiting")
    } catch (error) {
      // Service workers are optional; a plain reload still picks up the new build.
    }

    setTimeout(() => window.location.reload(), 1500)
  }

  showNotice() {
    const notice = document.createElement("div")
    notice.className =
      "fixed bottom-4 left-1/2 -translate-x-1/2 z-50 rounded-lg bg-purple-600 text-white " +
      "px-4 py-2 text-sm shadow-lg flex items-center gap-2"
    notice.setAttribute("role", "status")
    notice.textContent = "A new version of Lievik is available — refreshing…"
    document.body.appendChild(notice)
  }
}
