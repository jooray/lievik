import { Controller } from "@hotwired/stimulus"
import { t } from "../lib/i18n"

// Connects to data-controller="template-selector"
export default class extends Controller {
  static targets = ["textarea"]

  loadTemplate(event) {
    event.preventDefault()
    const content = event.params.content

    if (this.hasTextareaTarget && content) {
      // If textarea has content, confirm replacement
      if (this.textareaTarget.value.trim() && this.textareaTarget.value.trim() !== content.trim()) {
        if (!confirm(t("template_selector.replace_confirm"))) {
          return
        }
      }

      this.textareaTarget.value = content
      // Trigger input event for any listeners
      this.textareaTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
}
