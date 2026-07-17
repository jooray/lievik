import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="template-selector"
export default class extends Controller {
  static targets = ["textarea"]

  loadTemplate(event) {
    event.preventDefault()
    const content = event.params.content

    if (this.hasTextareaTarget && content) {
      // If textarea has content, confirm replacement
      if (this.textareaTarget.value.trim() && this.textareaTarget.value.trim() !== content.trim()) {
        if (!confirm("Replace current content with this template?")) {
          return
        }
      }

      this.textareaTarget.value = content
      // Trigger input event for any listeners
      this.textareaTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
}
