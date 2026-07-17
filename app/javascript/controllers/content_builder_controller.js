import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["refineInput", "form", "editorContainer"]
  static values = { streamUrl: String, refineUrl: String, autoGenerate: Boolean }

  connect() {
    this.eventSource = null
    this.streamPhase = null
    this.hasReplacementContent = false

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
    if (this.eventSource) {
      this.eventSource.close()
    }
  }

  resetStreamState() {
    this.streamPhase = null
    this.hasReplacementContent = false
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

    // Connect to SSE endpoint
    this.eventSource = new EventSource(streamUrl)

    this.eventSource.addEventListener("phase", (event) => {
      const data = JSON.parse(event.data)
      this.streamPhase = data.phase
      this.hasReplacementContent = false

      if (data.phase === "generating") {
        statusEl.textContent = "Generating content..."
      } else if (data.phase === "humanizing") {
        statusEl.textContent = "Humanizing content..."
      }
    })

    this.eventSource.addEventListener("chunk", (event) => {
      const chunk = JSON.parse(event.data)

      if (this.streamPhase === "humanizing" && !this.hasReplacementContent) {
        contentEl.textContent = ""
        this.hasReplacementContent = true
      }

      contentEl.textContent += chunk
    })

    this.eventSource.addEventListener("complete", (event) => {
      this.eventSource.close()
      statusEl.textContent = "Generation complete!"
      spinnerEl.classList.remove("animate-spin")
      spinnerEl.innerHTML = `
        <svg class="w-5 h-5 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>
      `
      // Reload page after short delay to show editor with saved content
      setTimeout(() => {
        window.location.reload()
      }, 1000)
    })

    this.eventSource.addEventListener("error", (event) => {
      let errorMsg = "An error occurred"
      try {
        const data = JSON.parse(event.data)
        errorMsg = data.message || errorMsg
      } catch (e) {
        // SSE connection error
        errorMsg = "Connection lost. Please try again."
      }

      this.eventSource.close()
      statusEl.textContent = "Error: " + errorMsg
      spinnerEl.classList.remove("animate-spin")
      spinnerEl.innerHTML = `
        <svg class="w-5 h-5 text-red-600 dark:text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      `
    })

    this.eventSource.onerror = (event) => {
      if (this.eventSource.readyState === EventSource.CLOSED) {
        return // Already handled
      }
      this.eventSource.close()
      statusEl.textContent = "Connection error. Please try again."
      spinnerEl.classList.remove("animate-spin")
    }
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

    // Build URL with prompt parameter
    const url = new URL(refineUrl, window.location.origin)
    url.searchParams.set("user_prompt", prompt)

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
            <p class="text-xs text-blue-700 dark:text-blue-300">Instruction: ${prompt}</p>
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

    // Connect to SSE endpoint
    this.eventSource = new EventSource(url.toString())

    this.eventSource.addEventListener("phase", (event) => {
      const data = JSON.parse(event.data)
      this.streamPhase = data.phase
      this.hasReplacementContent = false

      if (data.phase === "refining") {
        statusEl.textContent = "Refining content..."
      } else if (data.phase === "humanizing") {
        statusEl.textContent = "Humanizing content..."
      }
    })

    this.eventSource.addEventListener("chunk", (event) => {
      const chunk = JSON.parse(event.data)

      if (this.streamPhase === "humanizing" && !this.hasReplacementContent) {
        contentEl.textContent = ""
        this.hasReplacementContent = true
      }

      contentEl.textContent += chunk
    })

    this.eventSource.addEventListener("complete", (event) => {
      this.eventSource.close()
      statusEl.textContent = "Refinement complete!"
      spinnerEl.classList.remove("animate-spin")
      spinnerEl.innerHTML = `
        <svg class="w-5 h-5 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>
      `
      setTimeout(() => {
        window.location.reload()
      }, 1000)
    })

    this.eventSource.addEventListener("error", (event) => {
      let errorMsg = "An error occurred"
      try {
        const data = JSON.parse(event.data)
        errorMsg = data.message || errorMsg
      } catch (e) {
        errorMsg = "Connection lost. Please try again."
      }

      this.eventSource.close()
      statusEl.textContent = "Error: " + errorMsg
      spinnerEl.classList.remove("animate-spin")
      spinnerEl.innerHTML = `
        <svg class="w-5 h-5 text-red-600 dark:text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      `
    })

    this.eventSource.onerror = (event) => {
      if (this.eventSource.readyState === EventSource.CLOSED) {
        return
      }
      this.eventSource.close()
      statusEl.textContent = "Connection error. Please try again."
      spinnerEl.classList.remove("animate-spin")
    }
  }
}
