import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form", "textarea"]

  edit(event) {
    if (event) event.preventDefault()

    this.displayTargets.forEach((target) => target.classList.add("hidden"))
    this.formTarget.classList.remove("hidden")
    this.textareaTarget.focus()
    this.textareaTarget.setSelectionRange(this.textareaTarget.value.length, this.textareaTarget.value.length)
  }

  cancel(event) {
    if (event) event.preventDefault()

    this.formTarget.classList.add("hidden")
    this.displayTargets.forEach((target) => target.classList.remove("hidden"))
  }
}
