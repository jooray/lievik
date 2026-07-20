import { Controller } from "@hotwired/stimulus"

// Cards are wrapped in a <label>, so a click anywhere inside them toggles the
// selection checkbox. Interactive children (links, buttons) attach this to keep
// their own click from bubbling up and selecting the card as a side effect.
//
// Deliberately does not preventDefault — the link must still navigate.
export default class extends Controller {
  stop(event) {
    event.stopPropagation()
  }
}
