import { Controller } from "@hotwired/stimulus"

// Live numeric readout for a range input, replacing an inline oninput handler
// (CSP blocks those).
export default class extends Controller {
  static targets = ["input", "output"]
  static values = { suffix: { type: String, default: "" } }

  connect() {
    this.update()
  }

  update() {
    if (!this.hasInputTarget || !this.hasOutputTarget) return

    this.outputTarget.textContent = `${this.inputTarget.value}${this.suffixValue}`
  }
}
