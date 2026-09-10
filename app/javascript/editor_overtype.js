// Markdown editor implementation: OverType. This is a *separate esbuild entry
// point*, not part of application.js — the editor is only needed on ~4 pages,
// and CodeMirror used to be 67% of the app bundle on every single page.
//
// It has to be an entry point rather than a dynamic import(): esbuild here runs
// without --splitting and Propshaft serves digested paths only, so a code-split
// chunk would 404 in production. `markdown_editor_tags` (ApplicationHelper)
// decides which of these bundles a page loads; only one is ever sent.
//
// The page-facing contract is `window.LievikEditor`, shared with
// editor_easymde.js — see markdown_editor_controller.js.
import OverType from "overtype"

// OverType's own solar/cave themes look like a foreign widget in here, so the
// palettes are built from the app's colours: purple accents in light mode,
// the warm amber of the dark theme in dark mode.
const LIGHT_THEME = {
  name: "lievik-light",
  colors: {
    bgPrimary: "#ffffff", bgSecondary: "#ffffff",
    text: "#111827", textPrimary: "#111827", textSecondary: "#6b7280",
    h1: "#5b21b6", h2: "#7c3aed", h3: "#9333ea",
    strong: "#111827", em: "#374151", del: "#6b7280",
    link: "#2563eb", code: "#9333ea", codeBg: "rgba(147, 51, 234, 0.08)",
    blockquote: "#6b7280", hr: "#d1d5db",
    syntaxMarker: "rgba(107, 114, 128, 0.55)", syntax: "#9ca3af",
    cursor: "#9333ea", selection: "rgba(147, 51, 234, 0.15)",
    listMarker: "#9333ea", rawLine: "#6b7280",
    border: "#d1d5db", hoverBg: "#f9fafb", primary: "#9333ea",
    toolbarBg: "#ffffff", toolbarIcon: "#4b5563",
    toolbarHover: "#f3f4f6", toolbarActive: "#ede9fe",
    placeholder: "#9ca3af"
  }
}

const DARK_THEME = {
  name: "lievik-dark",
  colors: {
    bgPrimary: "#141414", bgSecondary: "#1c1c1c",
    text: "#e5e5e5", textPrimary: "#e5e5e5", textSecondary: "#a3a3a3",
    h1: "#fbbf24", h2: "#d97706", h3: "#e5e5e5",
    strong: "#fbbf24", em: "#a3a3a3", del: "#a3a3a3",
    link: "#38bdf8", code: "#4ade80", codeBg: "#0a0a0a",
    blockquote: "#a3a3a3", hr: "#525252",
    syntaxMarker: "rgba(163, 163, 163, 0.6)", syntax: "#525252",
    cursor: "#fbbf24", selection: "rgba(217, 119, 6, 0.25)",
    listMarker: "#d97706", rawLine: "#a3a3a3",
    border: "#2a2a2a", hoverBg: "#262626", primary: "#d97706",
    toolbarBg: "#141414", toolbarIcon: "#a3a3a3",
    toolbarHover: "#262626", toolbarActive: "#1c1c1c",
    placeholder: "#525252"
  }
}

// OverType builds its stylesheet at runtime and appends a <style> to <head>,
// with no nonce option of its own. Under `style-src 'self' 'nonce-…'` that
// element is blocked and the editor renders completely unstyled — the invisible
// textarea stops lining up with the preview underneath it, which is the whole
// trick. Stamping the nonce before insertion is what lets it through; the
// attribute has to be set on the element *before* it enters the document.
function applyTheme() {
  const theme = document.documentElement.classList.contains("dark") ? DARK_THEME : LIGHT_THEME
  const nonce = document.querySelector("meta[name=csp-nonce]")?.content

  if (!nonce) {
    OverType.setTheme(theme)
    return
  }

  const append = document.head.appendChild.bind(document.head)
  document.head.appendChild = (element) => {
    if (element.tagName === "STYLE") element.nonce = nonce
    return append(element)
  }

  try {
    OverType.setTheme(theme)
  } finally {
    document.head.appendChild = append
  }
}

applyTheme()

// theme_controller.js fires this whenever the mode changes; without it the
// editor stays in light colours inside a dark page.
document.addEventListener("lievik:theme", applyTheme)

window.LievikEditor = {
  name: "overtype",

  mount(textarea, { placeholder, minHeight, onChange }) {
    // The Rails textarea stays in the form and stays authoritative — it is what
    // gets posted. OverType renders into a sibling.
    textarea.classList.add("hidden")

    const mountPoint = document.createElement("div")
    textarea.insertAdjacentElement("afterend", mountPoint)

    const [editor] = new OverType(mountPoint, {
      toolbar: true,
      value: textarea.value,
      placeholder,
      autoResize: true,
      // These two go through parseInt(), so px only: "70vh" silently becomes
      // 70 pixels and the editor collapses to one line.
      minHeight,
      maxHeight: "800px",
      // The reason to be here at all, half of it: this is a real <textarea>, so
      // the browser's spellchecker and mobile autocorrect work. CodeMirror
      // could not do this, which is why the old editor passed spellChecker:false.
      spellcheck: true,
      smartLists: true,
      // Fires from inside the constructor, before `editor` is assigned — the
      // handler must not reach back into this object.
      onChange: (value) => onChange(value)
    })

    return {
      getValue: () => editor.getValue(),
      setValue: (value) => editor.setValue(value),
      destroy() {
        editor.destroy()
        mountPoint.remove()
        textarea.classList.remove("hidden")
      }
    }
  }
}

// Turbo can append this script to <head> after the Stimulus controller has
// already connected, so announce readiness instead of assuming load order.
document.dispatchEvent(new Event("lievik:editor-ready"))
