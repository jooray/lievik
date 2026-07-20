import { Controller } from "@hotwired/stimulus"
import EasyMDE from "easymde"

// NOTE: EasyMDE + CodeMirror is the bulk of the JS bundle and is only needed on
// ~4 pages, but it is imported statically on purpose. esbuild here runs without
// --splitting, and Propshaft serves digested paths only, so a dynamic import()
// chunk would 404 in production. The render-blocking *stylesheet* is deferred
// instead (see content_for :head in the views that use this controller).
export default class extends Controller {
  static targets = ["textarea"]
  static values = { placeholder: String }

  connect() {
    const placeholder = this.hasPlaceholderValue
      ? this.placeholderValue
      : "Type your content here..."

    this.editor = new EasyMDE({
      element: this.textareaTarget,
      // Left at its default, EasyMDE appends a <link> to
      // maxcdn.bootstrapcdn.com for Font Awesome, which is what draws every
      // toolbar icon. `style-src :self` blocks it, so the toolbar rendered as a
      // row of blank buttons with only the separators visible. Icons are
      // self-hosted instead (see the .editor-toolbar rules in
      // application.tailwind.css) — one less third-party request, and the
      // toolbar no longer depends on a CDN being up.
      autoDownloadFontAwesome: false,
      spellChecker: false,
      autosave: {
        enabled: false
      },
      toolbar: [
        "bold", "italic", "heading", "|",
        "quote", "unordered-list", "ordered-list", "|",
        "link", "|",
        "preview", "side-by-side", "fullscreen", "|",
        "guide"
      ],
      status: false,
      minHeight: "300px",
      placeholder: placeholder,
      renderingConfig: {
        singleLineBreaks: false,
        codeSyntaxHighlighting: false
      }
    })

    // Keep the textarea in sync so the "Save Changes" dirty-state fires while
    // typing in the editor, not only on submit.
    this.editor.codemirror.on("change", () => {
      this.textareaTarget.value = this.editor.value()
      this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }))
    })

    // Handle form submission - sync editor content back to textarea
    this.form = this.element.closest("form")
    if (this.form) {
      this.onSubmit = () => { this.textareaTarget.value = this.editor.value() }
      this.form.addEventListener("submit", this.onSubmit)
    }
  }

  disconnect() {
    if (this.form && this.onSubmit) {
      this.form.removeEventListener("submit", this.onSubmit)
      this.form = null
      this.onSubmit = null
    }

    if (this.editor) {
      this.editor.toTextArea()
      this.editor = null
    }
  }
}
