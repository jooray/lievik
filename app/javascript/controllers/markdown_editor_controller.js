import { Controller } from "@hotwired/stimulus"

// The editor library itself is NOT imported here. It lives in a separate
// esbuild entry point (editor_overtype.js, or editor_easymde.js for a user with
// the escape hatch set) that only the pages with an editor pull in, via
// `markdown_editor_tags`. Importing it here would put it back in
// application.js, which is how CodeMirror ended up on every page in the app.
//
// What stays here is everything that is identical whichever implementation
// loads: keeping the Rails textarea in sync so the form posts the right value,
// and firing `input` so content_editor_controller's dirty state flips while
// typing rather than only on submit.
export default class extends Controller {
  static targets = ["textarea"]
  static values = { placeholder: String, minHeight: String }

  connect() {
    this.editor = null

    // Turbo appends the editor bundle to <head> on navigation, which can happen
    // after this controller connects, so wait for the announcement rather than
    // assuming script order.
    if (window.LievikEditor) {
      this.mount()
    } else {
      this.onReady = () => this.mount()
      document.addEventListener("lievik:editor-ready", this.onReady, { once: true })
    }
  }

  mount() {
    if (this.editor || !this.hasTextareaTarget) return

    this.editor = window.LievikEditor.mount(this.textareaTarget, {
      placeholder: this.hasPlaceholderValue ? this.placeholderValue : "Type your content here...",
      minHeight: this.hasMinHeightValue ? this.minHeightValue : "300px",
      onChange: (value) => this.sync(value)
    })

    this.form = this.element.closest("form")
    if (this.form) {
      this.onSubmit = () => this.sync(this.editor.getValue())
      this.form.addEventListener("submit", this.onSubmit)
    }
  }

  sync(value) {
    this.textareaTarget.value = value
    this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  disconnect() {
    if (this.onReady) {
      document.removeEventListener("lievik:editor-ready", this.onReady)
      this.onReady = null
    }

    if (this.form && this.onSubmit) {
      this.form.removeEventListener("submit", this.onSubmit)
      this.form = null
      this.onSubmit = null
    }

    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  }
}
