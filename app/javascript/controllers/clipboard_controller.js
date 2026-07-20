import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  // For read-only inputs: clicking selects the whole value so it can be copied
  // manually. Replaces an inline `onclick="this.select()"`, which CSP blocks.
  selectAll() {
    this.element.select?.()
  }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      const original = this.element.textContent
      this.element.textContent = "Copied!"
      setTimeout(() => {
        this.element.textContent = original
      }, 1500)
    })
  }
}
