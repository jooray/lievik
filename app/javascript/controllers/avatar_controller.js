import { Controller } from "@hotwired/stimulus"

// Profile pictures are hotlinked from arbitrary hosts named in a Nostr kind:0
// profile. When one blocks hotlinking or disappears, the browser paints a
// permanent broken-image icon; swap in the initial-letter avatar instead.
//
// The fallback is a Stimulus action rather than an inline `onerror` because CSP
// (`script-src 'self'`) will not run inline handlers.
export default class extends Controller {
  static targets = ["image", "fallback"]

  fallback() {
    if (this.hasImageTarget) this.imageTarget.classList.add("hidden")
    if (this.hasFallbackTarget) this.fallbackTarget.classList.remove("hidden")
  }
}
