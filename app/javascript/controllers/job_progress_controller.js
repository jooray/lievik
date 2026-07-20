import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.hadJobs = this.containerTarget.children.length > 0
    this.observer = new MutationObserver(() => this.checkChildren())
    this.observer.observe(this.containerTarget, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  checkChildren() {
    const hasChildren = this.containerTarget.children.length > 0
    if (hasChildren) {
      this.element.classList.remove("hidden")
      this.hadJobs = true
    } else if (this.hadJobs) {
      // All jobs finished — refresh the content feed. A Turbo visit re-renders
      // in place and keeps scroll position, unlike window.location.reload().
      this.hadJobs = false
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }
}
