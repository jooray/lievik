import { Controller } from "@hotwired/stimulus"
import { t, locale } from "../lib/i18n"

// Plural-aware lookup: picks `<key>.one|few|other` for the page's locale
// (Slovak and Czech need "few"), falling back to `other`.
function tp(key, count, vars = {}) {
  let category = "other"
  try { category = new Intl.PluralRules(locale()).select(count) } catch (e) { /* keep "other" */ }
  const full = `${key}.${category}`
  const text = t(full, { count, ...vars })
  return text === full ? t(`${key}.other`, { count, ...vars }) : text
}

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
      this.countTarget.textContent = tp("bulk_select.selected", checkedCount)
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
      // The label element says which kind it is: data-bulk-select-kind=
      // "rerate" (events page) or "mark-used" (channel page). Detected by
      // attribute, not by the label text, because the label is translated.
      const isRerate = this.submitTextTarget.dataset.bulkSelectKind === "rerate"

      if (isRerate) {
        if (checkedCount === 0) {
          text = t("bulk_select.rerate_all", { count: this.totalValue })
        } else {
          text = tp("bulk_select.rerate_n", checkedCount)
        }
      } else {
        if (checkedCount === 0) {
          text = t("bulk_select.mark_used")
        } else {
          text = t("bulk_select.mark_n", { count: checkedCount })
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
        this.contentSubmitTextTarget.value = t("bulk_select.use_events")
      } else {
        this.contentSubmitTextTarget.value = tp("bulk_select.use_n", checkedCount)
      }
    }
  }
}
