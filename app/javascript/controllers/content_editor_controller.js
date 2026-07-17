import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "saveBtn"]

  connect() {
    // Track if content has changed
    this.originalContent = this.hasTextareaTarget ? this.textareaTarget.value : ""

    if (this.hasTextareaTarget) {
      this.textareaTarget.addEventListener("input", this.handleInput.bind(this))
    }
  }

  handleInput() {
    const hasChanges = this.textareaTarget.value !== this.originalContent

    if (this.hasSaveBtnTarget) {
      if (hasChanges) {
        this.saveBtnTarget.classList.remove("bg-blue-600", "hover:bg-blue-700")
        this.saveBtnTarget.classList.add("bg-orange-600", "hover:bg-orange-700")
        this.saveBtnTarget.textContent = "Save Changes"
      } else {
        this.saveBtnTarget.classList.remove("bg-orange-600", "hover:bg-orange-700")
        this.saveBtnTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
        this.saveBtnTarget.textContent = "Save Draft"
      }
    }
  }

  // Called after successful save to reset state
  resetState() {
    if (this.hasTextareaTarget) {
      this.originalContent = this.textareaTarget.value
    }
    this.handleInput()
  }
}
