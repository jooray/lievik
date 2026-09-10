// Markdown editor implementation: EasyMDE. Kept as an escape hatch behind
// `User#markdown_editor` (a settings key, no UI) while OverType settles in. It
// is a separate esbuild entry point, so a user on the default never downloads
// any of it — see editor_overtype.js for why this is an entry point and not a
// dynamic import.
//
// If OverType has held up, delete this file, `easymde` from package.json, the
// `cp easymde.min.css` step in build:css, and the .EasyMDEContainer block in
// application.tailwind.css.
import EasyMDE from "easymde"

window.LievikEditor = {
  name: "easymde",

  mount(textarea, { placeholder, minHeight, onChange }) {
    const editor = new EasyMDE({
      element: textarea,
      // Left at its default, EasyMDE appends a <link> to
      // maxcdn.bootstrapcdn.com for Font Awesome, which is what draws every
      // toolbar icon. `style-src :self` blocks it, so the toolbar rendered as a
      // row of blank buttons with only the separators visible. Icons are
      // self-hosted instead (see the .editor-toolbar rules in
      // application.tailwind.css) — one less third-party request, and the
      // toolbar no longer depends on a CDN being up.
      autoDownloadFontAwesome: false,
      spellChecker: false,
      autosave: { enabled: false },
      toolbar: [
        "bold", "italic", "heading", "|",
        "quote", "unordered-list", "ordered-list", "|",
        "link", "|",
        "preview", "side-by-side", "fullscreen", "|",
        "guide"
      ],
      status: false,
      minHeight,
      placeholder,
      renderingConfig: {
        singleLineBreaks: false,
        codeSyntaxHighlighting: false
      }
    })

    editor.codemirror.on("change", () => onChange(editor.value()))

    return {
      getValue: () => editor.value(),
      setValue: (value) => editor.value(value),
      destroy: () => editor.toTextArea()
    }
  }
}

document.dispatchEvent(new Event("lievik:editor-ready"))
