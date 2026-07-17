import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nip07Section", "divider", "extensionButton", "pollingIndicator", "errorMessage", "errorText", "config"]

  connect() {
    this.pollInterval = null
    this.checkNip07Extension()
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  checkNip07Extension() {
    // Check if NIP-07 extension is available
    if (typeof window.nostr !== "undefined") {
      this.nip07SectionTarget.classList.remove("hidden")
      this.dividerTarget.classList.remove("hidden")
    }
  }

  async loginWithExtension() {
    if (typeof window.nostr === "undefined") {
      this.showError("No NIP-07 extension found. Please install nos2x, Alby, or another Nostr extension.")
      return
    }

    this.extensionButtonTarget.disabled = true
    this.extensionButtonTarget.innerHTML = `
      <svg class="animate-spin h-5 w-5" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
      </svg>
      Connecting...
    `

    try {
      // Get public key from extension
      const pubkey = await window.nostr.getPublicKey()

      if (!pubkey) {
        this.showError("Failed to get public key from extension")
        this.resetButton()
        return
      }

      // Sign the challenge issued by this Rails session.
      const authEvent = {
        kind: 22242,
        created_at: Math.floor(Date.now() / 1000),
        tags: [["challenge", this.configTarget.dataset.nostrLoginChallenge]],
        content: "Sign in to Lievik"
      }

      // Sign the event
      const signedEvent = await window.nostr.signEvent(authEvent)

      const callbackUrl = this.configTarget.dataset.nostrLoginCallbackUrl
      const form = document.createElement("form")
      form.method = "post"
      form.action = callbackUrl
      form.innerHTML = `
        <input type="hidden" name="authenticity_token" value="${document.querySelector('meta[name="csrf-token"]').content}">
        <input type="hidden" name="signed_event">
      `
      form.querySelector('[name="signed_event"]').value = JSON.stringify(signedEvent)
      document.body.appendChild(form)
      form.submit()
    } catch (error) {
      console.error("NIP-07 login error:", error)
      this.showError(`Extension error: ${error.message || "Unknown error"}`)
      this.resetButton()
    }
  }

  startPolling() {
    const pollUrl = this.configTarget.dataset.nostrLoginPollUrl

    this.pollInterval = setInterval(async () => {
      try {
        const response = await fetch(pollUrl)
        const data = await response.json()

        if (data.authenticated) {
          this.stopPolling()
          window.location.href = data.redirect_url
        }
      } catch (error) {
        console.error("Polling error:", error)
      }
    }, 3000)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  showError(message) {
    this.errorMessageTarget.classList.remove("hidden")
    this.errorTextTarget.textContent = message
  }

  hideError() {
    this.errorMessageTarget.classList.add("hidden")
  }

  resetButton() {
    this.extensionButtonTarget.disabled = false
    this.extensionButtonTarget.innerHTML = `
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
      </svg>
      Sign in with Browser Extension
    `
  }

}
