import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "checkbox", "count", "actions", "form", "submitText", "checkboxes", "contentForm", "contentCheckboxes", "contentSubmitText"]
  static values = { total: Number }

  connect() {
    this.updateCount()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach((checkbox) => {
      // Skip disabled checkboxes (e.g., already used items)
      if (!checkbox.disabled) {
        checkbox.checked = checked
      }
    })
    this.updateCount()
  }

  updateCount() {
    const enabledCheckboxes = this.checkboxTargets.filter(cb => !cb.disabled)
    const checkedCount = this.checkboxTargets.filter(cb => cb.checked).length
    const enabledCount = enabledCheckboxes.length
    const pageTotal = this.checkboxTargets.length
    const selectedIds = this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.value)

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${checkedCount} selected`
    }

    if (this.hasActionsTarget) {
      if (checkedCount > 0) {
        this.actionsTarget.classList.remove("hidden")
      } else {
        this.actionsTarget.classList.add("hidden")
      }
    }

    // Update ALL forms' hidden fields (use plural targets to get all elements)
    this.checkboxesTargets.forEach(target => {
      target.value = JSON.stringify(selectedIds)
    })

    this.contentCheckboxesTargets.forEach(target => {
      target.value = JSON.stringify(selectedIds)
    })

    if (this.hasSelectAllTarget) {
      // Use enabledCount for selectAll state (ignore disabled checkboxes like already-used items)
      this.selectAllTarget.checked = checkedCount === enabledCount && enabledCount > 0
      this.selectAllTarget.indeterminate = checkedCount > 0 && checkedCount < enabledCount
    }

    if (this.hasSubmitTextTarget) {
      let text
      // Check if this is the events page (rerate) or channel page (mark as used)
      const isRerate = this.submitTextTarget.textContent.includes('Rerate')

      if (isRerate) {
        if (checkedCount === 0) {
          text = `Rerate All (${this.totalValue})`
        } else {
          text = `Rerate ${checkedCount} Event${checkedCount !== 1 ? 's' : ''}`
        }
      } else {
        if (checkedCount === 0) {
          text = `Mark as Used`
        } else {
          text = `Mark ${checkedCount} as Used`
        }
      }

      // Handle both span and input elements
      if (this.submitTextTarget.tagName === 'SPAN') {
        this.submitTextTarget.textContent = text
      } else {
        this.submitTextTarget.value = text
      }
    }

    if (this.hasContentSubmitTextTarget) {
      if (checkedCount === 0) {
        this.contentSubmitTextTarget.value = `Use Events in new content`
      } else {
        this.contentSubmitTextTarget.value = `Use ${checkedCount} Event${checkedCount !== 1 ? 's' : ''} in new content`
      }
    }
  }
}
