import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeSelect", "identifierLabel", "identifierInput", "identifierHint", "nostrSettings"]
  static values = { sourceType: String }

  connect() {
    this.updateFormForType()
  }

  typeChanged() {
    this.sourceTypeValue = this.typeSelectTarget.value
    this.updateFormForType()
  }

  updateFormForType() {
    const isNostr = this.sourceTypeValue === "nostr"

    // Update label
    this.identifierLabelTarget.textContent = isNostr
      ? "Nostr Public Key (npub)"
      : "Feed URL"

    // Update placeholder
    this.identifierInputTarget.placeholder = isNostr
      ? "npub1..."
      : "https://example.com/feed.xml"

    // Update hint
    this.identifierHintTarget.textContent = isNostr
      ? "Enter the npub or hex public key of the account"
      : "Enter the URL of the RSS or Atom feed"

    // Show/hide Nostr-specific settings
    if (this.hasNostrSettingsTarget) {
      this.nostrSettingsTarget.classList.toggle("hidden", !isNostr)
    }
  }
}
