import { Controller } from "@hotwired/stimulus"

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
      this.buttonTarget.textContent = "Show less"
    } else {
      this.shortTarget.classList.remove("hidden")
      this.fullTarget.classList.add("hidden")
      this.buttonTarget.textContent = "Show more"
    }
  }
}
