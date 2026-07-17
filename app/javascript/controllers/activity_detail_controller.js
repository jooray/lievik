import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["detailFrame", "toggle", "list"]
  static values = { selectedLog: Number }

  connect() {
    this.loadDevMode()
  }

  toggleDevMode(event) {
    localStorage.setItem("devModeActivityLogs", event.target.checked)
    this.updateVisibility()
  }

  select(event) {
    const logId = event.currentTarget.dataset.logId
    this.selectedLogValue = parseInt(logId)
    if (this.devModeActive()) {
      this.loadDetails()
    }
  }

  loadDetails() {
    if (this.hasDetailFrameTarget && this.selectedLogValue) {
      this.detailFrameTarget.src = `/activity_logs/${this.selectedLogValue}/dev_logs`
    }
  }

  devModeActive() {
    return localStorage.getItem("devModeActivityLogs") === "true" || this.toggleTarget?.checked
  }

  updateVisibility() {
    const active = this.devModeActive()
    if (this.hasDetailFrameTarget) {
      this.detailFrameTarget.classList.toggle("hidden", !active)
    }
    if (this.hasListTarget) {
      this.listTarget.classList.toggle("lg:col-span-2", !active)
      this.listTarget.classList.toggle("lg:col-span-1", active)
    }
  }

  loadDevMode() {
    const saved = localStorage.getItem("devModeActivityLogs")
    if (this.hasToggleTarget && saved !== null) {
      this.toggleTarget.checked = saved === "true"
    }
    this.updateVisibility()
  }
}
