import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }
  // Optional. Without it the whole element's text is swapped for the "Copied!"
  // feedback, which would wipe out an icon sitting next to the label.
  static targets = ["label"]

  // For read-only inputs: clicking selects the whole value so it can be copied
  // manually. Replaces an inline `onclick="this.select()"`, which CSP blocks.
  selectAll() {
    this.element.select?.()
  }

  copy() {
    const feedbackElement = this.hasLabelTarget ? this.labelTarget : this.element

    navigator.clipboard.writeText(this.textValue).then(() => {
      const original = feedbackElement.textContent
      feedbackElement.textContent = "Copied!"
      setTimeout(() => {
        feedbackElement.textContent = original
      }, 1500)
    }).catch(() => {
      const original = feedbackElement.textContent
      feedbackElement.textContent = "Copy failed"
      setTimeout(() => {
        feedbackElement.textContent = original
      }, 1500)
    })
  }
}
