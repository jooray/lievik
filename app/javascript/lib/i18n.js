// Client-side strings. The layout renders the current locale's `js.*` keys
// (English-backfilled) into <script type="application/json" id="lievik-i18n">
// inside <body>, so a Turbo visit after a language switch swaps them too.
//
//   import { t } from "../lib/i18n"
//   t("rag_chat.copy")                    // => "Kopírovať"
//   t("rag_chat.sources", { count: 3 })   // %{count} interpolation

let cachedElement = null
let cachedStrings = {}

function strings() {
  const el = document.getElementById("lievik-i18n")
  if (el !== cachedElement) {
    cachedElement = el
    try {
      cachedStrings = el ? JSON.parse(el.textContent) : {}
    } catch (e) {
      cachedStrings = {}
    }
  }
  return cachedStrings
}

export function t(key, vars = {}) {
  const value = key.split(".").reduce((node, part) => (node == null ? node : node[part]), strings())
  const text = typeof value === "string" ? value : key
  return text.replace(/%\{(\w+)\}/g, (_, name) => (vars[name] == null ? "" : String(vars[name])))
}

export function locale() {
  return document.documentElement.lang || "en"
}
