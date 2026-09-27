import { Controller } from "@hotwired/stimulus"
import { t } from "../lib/i18n"

export default class extends Controller {
  static targets = ["short", "full", "button"]

  connect() {
    this.isExpanded = false
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    this.isExpanded = !this.isExpanded

    if (this.isExpanded) {
      this.shortTarget.classList.add("hidden")
      this.fullTarget.classList.remove("hidden")
      this.buttonTarget.textContent = t("event_expander.show_less")
    } else {
      this.shortTarget.classList.remove("hidden")
      this.fullTarget.classList.add("hidden")
      this.buttonTarget.textContent = t("event_expander.show_more")
    }
  }
}
