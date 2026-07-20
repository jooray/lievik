import { Controller } from "@hotwired/stimulus"

// Dismissable flash message. Kept deliberately tiny: the close button just
// removes the element (no animation state to get stuck in).
export default class extends Controller {
  dismiss() {
    this.element.remove()
  }
}
