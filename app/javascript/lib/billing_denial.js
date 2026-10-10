import { t } from "./i18n"

// On the hosted instance an AI request can be refused before its stream
// starts: 402 paywall, 429 daily cap, 503 billing down. The server answers
// those as JSON with a `code` (BillingGate). Returns { message, billingUrl }
// for such a response, or null for any other failure.
export async function readBillingDenial(response) {
  if (!(response.headers.get("Content-Type") || "").includes("application/json")) return null

  const data = await response.json().catch(() => null)
  if (!data || !data.code || !data.error) return null

  return { message: data.error, billingUrl: data.billing_url }
}

// Replaces el's content with the denial, plus a link to the billing page for
// a paywall.
export function showBillingDenial(el, denial, className = "text-red-500") {
  const message = document.createElement("span")
  message.className = className
  message.textContent = denial.message
  el.replaceChildren(message)

  if (denial.billingUrl) {
    const link = document.createElement("a")
    link.href = denial.billingUrl
    link.className = "ml-1 font-medium underline"
    link.textContent = t("billing.open_plans")
    el.append(" ", link)
  }
}
