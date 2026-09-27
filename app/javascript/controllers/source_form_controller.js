import { Controller } from "@hotwired/stimulus"
import { t } from "../lib/i18n"

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
      ? t("source_form.nostr_label")
      : t("source_form.rss_label")

    // Update placeholder
    this.identifierInputTarget.placeholder = isNostr
      ? "npub1..."
      : "https://example.com/feed.xml"

    // Update hint
    this.identifierHintTarget.textContent = isNostr
      ? t("source_form.nostr_hint")
      : t("source_form.rss_hint")

    // Show/hide Nostr-specific settings
    if (this.hasNostrSettingsTarget) {
      this.nostrSettingsTarget.classList.toggle("hidden", !isNostr)
    }
  }
}
