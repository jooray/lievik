import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Both stream endpoints mutate the draft (they save a version and overwrite the
// content), so they are POST — which rules out EventSource. We POST with fetch()
// and parse the SSE frames off the response body ourselves; the streaming UX is
// identical, and the CSRF token travels in the request headers.
export default class extends Controller {
  static targets = ["refineInput", "form", "editorContainer"]
  static values = { streamUrl: String, refineUrl: String, autoGenerate: Boolean }

  connect() {
    this.abortController = null
    this.streamPhase = null
    this.hasReplacementContent = false
    this.streaming = false

    // Auto-start streaming if flag is set
    if (this.autoGenerateValue) {
      const cleanUrl = new URL(window.location.href)
      cleanUrl.searchParams.delete("auto_generate")
      window.history.replaceState({}, "", cleanUrl)

      // Small delay to ensure DOM is ready
      setTimeout(() => this.startStreaming(), 100)
    }
  }

  disconnect() {
    this.abortStream()
  }

  abortStream() {
    if (this.abortController) {
      this.abortController.abort()
      this.abortController = null
    }
  }

  resetStreamState() {
    this.streamPhase = null
    this.hasReplacementContent = false
  }

  // A second click while a stream is open would start a parallel generation:
  // two writes to the same draft, two version-history entries, and double the
  // API spend. Guard the entry points and grey out the triggers.
  beginStreaming() {
    if (this.streaming) return false

    this.streaming = true
    this.setTriggersDisabled(true)
    return true
  }

  endStreaming() {
    this.streaming = false
    this.setTriggersDisabled(false)
  }

  setTriggersDisabled(disabled) {
    this.element
      .querySelectorAll('button[data-action*="content-builder#"], input[data-action*="content-builder#"]')
      .forEach((trigger) => {
        trigger.disabled = disabled
        trigger.classList.toggle("opacity-50", disabled)
        trigger.classList.toggle("cursor-not-allowed", disabled)
      })
  }

  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }

  // POST to an SSE endpoint and dispatch each frame to `handlers`, keyed by the
  // SSE `event:` name. Resolves when the server closes the stream.
  async streamSse(url, body, handlers) {
    this.abortStream()
    const controller = new AbortController()
    this.abortController = controller

    let response
    try {
      response = await fetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify(body || {}),
        signal: controller.signal
      })
    } catch (e) {
      if (!controller.signal.aborted) {
        handlers.error({ message: "Connection error. Please try again." })
      }
      return
    }

    if (!response.ok || !response.body) {
      handlers.error({ message: `Request failed (${response.status}). Please try again.` })
      return
    }

    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""

    while (true) {
      let result
      try {
        result = await reader.read()
      } catch (e) {
        if (!controller.signal.aborted) {
          handlers.error({ message: "Connection lost. Please try again." })
        }
        return
      }

      if (result.done) break

      buffer += decoder.decode(result.value, { stream: true })

      let boundary
      while ((boundary = buffer.indexOf("\n\n")) !== -1) {
        const frame = buffer.slice(0, boundary)
        buffer = buffer.slice(boundary + 2)
        this.dispatchSseFrame(frame, handlers)
      }
    }
  }

  dispatchSseFrame(frame, handlers) {
    let eventName = "message"
    const dataLines = []

    frame.split("\n").forEach((line) => {
      if (line.startsWith("event:")) {
        eventName = line.slice(6).trim()
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).replace(/^ /, ""))
      }
    })

    if (dataLines.length === 0) return

    let data
    try {
      data = JSON.parse(dataLines.join("\n"))
    } catch (e) {
      data = dataLines.join("\n")
    }

    const handler = handlers[eventName]
    if (handler) handler(data)
  }

  // Shared success/failure chrome for both streams
  streamHandlers({ contentEl, statusEl, spinnerEl, phaseLabels, doneLabel }) {
    return {
      phase: (data) => {
        this.streamPhase = data.phase
        this.hasReplacementContent = false
        const label = phaseLabels[data.phase]
        if (label) statusEl.textContent = label
      },

      chunk: (chunk) => {
        if (this.streamPhase === "humanizing" && !this.hasReplacementContent) {
          contentEl.textContent = ""
          this.hasReplacementContent = true
        }
        contentEl.textContent += chunk
      },

      complete: () => {
        this.abortController = null
        statusEl.textContent = doneLabel
        spinnerEl.classList.remove("animate-spin")
        spinnerEl.innerHTML = `
          <svg class="w-5 h-5 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
          </svg>
        `
        // Refresh to show the editor with the saved content. Turbo.visit keeps
        // scroll position and history instead of a hard reload.
        setTimeout(() => {
          this.endStreaming()
          Turbo.visit(window.location.href, { action: "replace" })
        }, 1000)
      },

      error: (data) => {
        this.abortStream()
        this.endStreaming()
        const message = (data && data.message) || "An error occurred"
        statusEl.textContent = "Error: " + message
        spinnerEl.classList.remove("animate-spin")
        spinnerEl.innerHTML = `
          <svg class="w-5 h-5 text-red-600 dark:text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        `
      }
    }
  }

  // Start streaming generation
  startStreaming(event = null) {
    if (event) event.preventDefault()

    const streamUrl = this.streamUrlValue
    if (!streamUrl) {
      console.error("No stream URL configured")
      return
    }

    const container = document.getElementById("editor-container")
    if (!container) return
    if (!this.beginStreaming()) return

    // Show initial streaming UI
    container.innerHTML = `
      <div class="space-y-4">
        <div class="flex items-center gap-3 p-4 bg-purple-50 dark:bg-purple-900/20 border border-purple-200 dark:border-purple-800 rounded-lg">
          <div class="animate-spin" id="streaming-spinner">
            <svg class="w-5 h-5 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-purple-900 dark:text-purple-200" id="streaming-status">Connecting to AI...</p>
            <p class="text-xs text-purple-700 dark:text-purple-300">Content will appear below as it's generated.</p>
          </div>
        </div>
        <div class="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 min-h-[400px]">
          <pre id="streaming-content" class="whitespace-pre-wrap text-sm text-gray-900 dark:text-gray-100 font-mono"></pre>
        </div>
      </div>
    `

    const contentEl = document.getElementById("streaming-content")
    const statusEl = document.getElementById("streaming-status")
    const spinnerEl = document.getElementById("streaming-spinner")
    this.resetStreamState()

    const handlers = this.streamHandlers({
      contentEl,
      statusEl,
      spinnerEl,
      phaseLabels: { generating: "Generating content...", humanizing: "Humanizing content..." },
      doneLabel: "Generation complete!"
    })

    this.streamSse(streamUrl, {}, handlers)
  }

  // Start streaming refinement
  startRefineStreaming(event = null) {
    if (event) event.preventDefault()

    const refineUrl = this.refineUrlValue
    if (!refineUrl) {
      console.error("No refine URL configured")
      return
    }

    const prompt = this.hasRefineInputTarget ? this.refineInputTarget.value.trim() : ""
    if (!prompt) {
      alert("Please enter instructions for the AI")
      return
    }

    const container = document.getElementById("editor-container")
    if (!container) return
    if (!this.beginStreaming()) return

    // Show initial streaming UI
    container.innerHTML = `
      <div class="space-y-4">
        <div class="flex items-center gap-3 p-4 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg">
          <div class="animate-spin" id="streaming-spinner">
            <svg class="w-5 h-5 text-blue-600 dark:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </div>
          <div>
            <p class="text-sm font-medium text-blue-900 dark:text-blue-200" id="streaming-status">Applying AI edits...</p>
            <p class="text-xs text-blue-700 dark:text-blue-300">Instruction: ${this.escapeHtml(prompt)}</p>
          </div>
        </div>
        <div class="p-4 bg-gray-50 dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 min-h-[400px]">
          <pre id="streaming-content" class="whitespace-pre-wrap text-sm text-gray-900 dark:text-gray-100 font-mono"></pre>
        </div>
      </div>
    `

    const contentEl = document.getElementById("streaming-content")
    const statusEl = document.getElementById("streaming-status")
    const spinnerEl = document.getElementById("streaming-spinner")
    this.resetStreamState()

    // Clear the input
    if (this.hasRefineInputTarget) {
      this.refineInputTarget.value = ""
    }

    const handlers = this.streamHandlers({
      contentEl,
      statusEl,
      spinnerEl,
      phaseLabels: { refining: "Refining content...", humanizing: "Humanizing content..." },
      doneLabel: "Refinement complete!"
    })

    this.streamSse(refineUrl, { user_prompt: prompt }, handlers)
  }
}
