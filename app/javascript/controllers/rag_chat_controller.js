import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messageList", "input", "submitButton", "loadingSpinner", "submitIcon"]
  static values = {
    streamUrl: String
  }

  connect() {
    this.messages = []
    this.isStreaming = false
    this.currentMessageWrapper = null
    this.input = this.inputTarget
    this.input.addEventListener("keydown", this.handleKeydown.bind(this))

    // Make controller accessible for hover events
    this.element.ragChatController = this
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.submit()
    }
  }

  async submit() {
    const question = this.input.value.trim()
    if (!question || this.isStreaming) return

    // Add user message to UI
    this.addUserMessage(question)
    this.input.value = ""
    this.input.style.height = "auto"

    // Start streaming
    this.setLoading(true)
    this.isStreaming = true

    // Add assistant message placeholder
    const { wrapper, contentDiv } = this.addAssistantMessage("")
    this.currentMessageWrapper = wrapper

    // Build conversation history for context
    const history = this.messages.slice(0, -1).map(m => ({
      role: m.role,
      content: m.content
    }))

    try {
      // Get CSRF token for POST request
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch(this.streamUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ question, history })
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let fullContent = ""
      let buffer = ""

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })

        // Parse SSE events from buffer
        const events = buffer.split("\n\n")
        buffer = events.pop() // Keep incomplete event in buffer

        for (const eventStr of events) {
          if (!eventStr.trim()) continue

          const lines = eventStr.split("\n")
          let eventType = null
          let eventData = null

          for (const line of lines) {
            if (line.startsWith("event: ")) {
              eventType = line.slice(7)
            } else if (line.startsWith("data: ")) {
              eventData = line.slice(6)
            }
          }

          if (eventType === "chunk" && eventData) {
            const chunk = JSON.parse(eventData)
            fullContent += chunk
            // Re-rendering the whole answer on every chunk is ~15 regex passes
            // plus a full innerHTML replacement — O(n^2) over a long answer, and
            // visibly janky. Coalesce to one render per animation frame.
            if (fullContent.trim()) {
              this.scheduleRender(contentDiv, () => fullContent)
            }
            this.scrollToBottom()
          } else if (eventType === "complete" && eventData) {
            this.cancelScheduledRender()
            const data = JSON.parse(eventData)
            this.isStreaming = false
            this.setLoading(false)

            const lastMessage = this.messages[this.messages.length - 1]
            if (lastMessage && lastMessage.role === "assistant") {
              lastMessage.content = this.cleanContent(fullContent)
            }

            contentDiv.innerHTML = this.renderMarkdown(fullContent)
            this.attachHoverListeners(contentDiv)

            const copyBtn = this.currentMessageWrapper.querySelector("[data-copy-button]")
            if (copyBtn) {
              copyBtn.classList.remove("hidden")
              copyBtn.setAttribute("data-raw-content", this.cleanContent(fullContent))
            }

            if (data.cited_events && data.cited_events.length > 0) {
              this.showSources(data.cited_events, this.currentMessageWrapper)
            }
          } else if (eventType === "error" && eventData) {
            const data = JSON.parse(eventData)
            contentDiv.innerHTML = `<span class="text-red-500">${this.escapeHtml(data.message || "An error occurred")}</span>`
            this.isStreaming = false
            this.setLoading(false)
          }
        }
      }

    } catch (error) {
      contentDiv.innerHTML = `<span class="text-red-500">Failed to connect: ${this.escapeHtml(error.message)}</span>`
      this.isStreaming = false
      this.setLoading(false)
    }
  }

  addUserMessage(content) {
    this.messages.push({ role: "user", content })

    const messageDiv = document.createElement("div")
    messageDiv.className = "grid grid-cols-1 lg:grid-cols-3 gap-4"
    messageDiv.setAttribute("data-chat-message", "")

    const contentCol = document.createElement("div")
    contentCol.className = "lg:col-span-2 flex flex-col items-end"

    const bubble = document.createElement("div")
    bubble.className = "max-w-3xl px-4 py-3 rounded-2xl bg-purple-600 text-white"
    bubble.innerHTML = this.escapeHtml(content)
    contentCol.appendChild(bubble)

    // Copy button below user message
    const copyBtn = document.createElement("button")
    copyBtn.className = "mt-1 p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
    copyBtn.setAttribute("data-raw-content", content)
    copyBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/>
    </svg>`
    copyBtn.addEventListener("click", () => this.copyToClipboard(copyBtn))
    contentCol.appendChild(copyBtn)

    messageDiv.appendChild(contentCol)

    // Empty right column for alignment
    const emptyCol = document.createElement("div")
    emptyCol.className = "lg:col-span-1"
    messageDiv.appendChild(emptyCol)

    this.messageListTarget.appendChild(messageDiv)
    this.scrollToBottom()
  }

  addAssistantMessage(content) {
    this.messages.push({ role: "assistant", content })

    const wrapper = document.createElement("div")
    wrapper.className = "grid grid-cols-1 lg:grid-cols-3 gap-4 items-stretch"
    wrapper.setAttribute("data-message-wrapper", "")
    wrapper.setAttribute("data-chat-message", "")

    // Left: Answer (2/3)
    const contentCol = document.createElement("div")
    contentCol.className = "lg:col-span-2"

    const bubble = document.createElement("div")
    bubble.className = "px-4 py-3 rounded-2xl bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100"

    // Content area
    const contentDiv = document.createElement("div")
    contentDiv.setAttribute("data-content", "")
    contentDiv.className = "prose prose-sm dark:prose-invert max-w-none"
    // Show thinking indicator when empty, actual content otherwise
    if (!content) {
      contentDiv.innerHTML = `<span class="text-gray-400 italic flex items-center gap-2">
        <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Thinking...
      </span>`
    } else {
      contentDiv.innerHTML = this.renderMarkdown(content)
    }
    bubble.appendChild(contentDiv)

    // Copy button - hidden initially, shown after generation completes
    const copyBtn = document.createElement("button")
    copyBtn.className = "mt-3 p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hidden"
    copyBtn.setAttribute("data-copy-button", "")
    copyBtn.setAttribute("data-raw-content", this.cleanContent(content))
    copyBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/>
    </svg>`
    copyBtn.addEventListener("click", () => this.copyToClipboard(copyBtn))
    bubble.appendChild(copyBtn)

    contentCol.appendChild(bubble)
    wrapper.appendChild(contentCol)

    // Right: Sources placeholder (1/3)
    const sourcesCol = document.createElement("div")
    sourcesCol.className = "lg:col-span-1"
    sourcesCol.setAttribute("data-sources-container", "")
    wrapper.appendChild(sourcesCol)

    this.messageListTarget.appendChild(wrapper)
    this.scrollToBottom()

    return { wrapper, contentDiv }
  }

  copyToClipboard(button) {
    const rawContent = button.getAttribute("data-raw-content")
    // Strip [EVENT:ID] references for clean copy, preserve newlines
    const cleanedContent = rawContent
      .replace(/\[EVENT:\d+\]/g, "")      // Remove citations
      .replace(/[ \t]+/g, " ")             // Collapse multiple spaces/tabs (not newlines)
      .replace(/\n /g, "\n")               // Remove space after newline
      .replace(/ \n/g, "\n")               // Remove space before newline
      .replace(/\n{3,}/g, "\n\n")          // Max 2 consecutive newlines
      .trim()
    navigator.clipboard.writeText(cleanedContent)

    // Visual feedback - show checkmark
    const originalHTML = button.innerHTML
    button.innerHTML = `<svg class="w-4 h-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
    </svg>`
    setTimeout(() => button.innerHTML = originalHTML, 2000)
  }

  showSources(events, messageWrapper) {
    const sourcesContainer = messageWrapper.querySelector("[data-sources-container]")
    if (!sourcesContainer) return

    if (!events.length) {
      sourcesContainer.innerHTML = ""
      return
    }

    sourcesContainer.innerHTML = `
      <div class="sticky top-4 bg-white dark:bg-gray-800 shadow rounded-lg flex flex-col max-h-[calc(100vh-8rem)] overflow-hidden">
        <div class="px-3 py-2 border-b border-gray-200 dark:border-gray-700 flex-shrink-0">
          <h3 class="text-sm font-medium text-gray-900 dark:text-white">Sources</h3>
        </div>
        <div class="p-3 space-y-2 overflow-y-auto flex-1" data-sources-scroll>
          ${events.map(event => `
            <div class="text-xs bg-gray-50 dark:bg-gray-900 rounded-lg p-2 transition-all duration-200"
                 data-source-id="${event.id}"
                 id="source-${event.id}">
              <div class="flex items-center justify-between mb-1">
                <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-bold bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200">
                  [${event.id}]
                </span>
                <span class="text-xs text-gray-500 dark:text-gray-400">${event.published_at || ''}</span>
              </div>
              <p class="font-medium text-gray-700 dark:text-gray-300 text-xs mb-1">${this.escapeHtml(event.source_name)}</p>
              <p class="text-gray-600 dark:text-gray-400 text-xs line-clamp-3">${this.escapeHtml(event.content)}</p>
              <a href="/events/${event.id}" class="text-xs text-purple-600 dark:text-purple-400 hover:underline mt-1 inline-block">
                View &rarr;
              </a>
            </div>
          `).join('')}
        </div>
      </div>
    `
  }

  attachHoverListeners(container) {
    // Find the message wrapper that contains this content
    const messageWrapper = container.closest('[data-message-wrapper]')
    const badges = container.querySelectorAll('[data-event-id]')
    badges.forEach(badge => {
      badge.addEventListener('mouseenter', () => {
        const id = badge.getAttribute('data-event-id')
        this.highlightSource(id, messageWrapper)
      })
      badge.addEventListener('mouseleave', () => {
        const id = badge.getAttribute('data-event-id')
        this.unhighlightSource(id, messageWrapper)
      })
    })
  }

  highlightSource(id, messageWrapper) {
    // Search within the message wrapper's sources, not the whole document
    const el = messageWrapper?.querySelector(`[data-source-id="${id}"]`)
    if (el) {
      el.classList.add('ring-2', 'ring-purple-500', 'bg-purple-50', 'dark:bg-purple-900/30')
      // Scroll within the sources container, not the page
      const scrollContainer = el.closest('[data-sources-scroll]')
      if (scrollContainer) {
        const elTop = el.offsetTop - scrollContainer.offsetTop
        const containerTop = scrollContainer.scrollTop
        const containerHeight = scrollContainer.clientHeight

        // Only scroll if element is not fully visible
        if (elTop < containerTop || elTop + el.offsetHeight > containerTop + containerHeight) {
          scrollContainer.scrollTo({
            top: Math.max(0, elTop - 10),
            behavior: 'smooth'
          })
        }
      }
    }
  }

  unhighlightSource(id, messageWrapper) {
    const el = messageWrapper?.querySelector(`[data-source-id="${id}"]`)
    if (el) {
      el.classList.remove('ring-2', 'ring-purple-500', 'bg-purple-50', 'dark:bg-purple-900/30')
    }
  }

  // Coalesce streaming re-renders into one per frame.
  scheduleRender(target, contentFn) {
    this.pendingRenderTarget = target
    this.pendingRenderContent = contentFn

    if (this.renderFrame) return

    this.renderFrame = requestAnimationFrame(() => {
      this.renderFrame = null
      if (!this.pendingRenderTarget) return
      this.pendingRenderTarget.innerHTML = this.renderMarkdown(this.pendingRenderContent())
    })
  }

  cancelScheduledRender() {
    if (this.renderFrame) {
      cancelAnimationFrame(this.renderFrame)
      this.renderFrame = null
    }
    this.pendingRenderTarget = null
    this.pendingRenderContent = null
  }

  renderMarkdown(content) {
    if (!content) return ""

    content = this.escapeHtml(content)
    let html = this.cleanContent(content)

    // Format [EVENT:ID] as badges BEFORE other markdown processing
    html = html.replace(/\[EVENT:(\d+)\]/g,
      '<span class="citation-badge inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200 cursor-pointer hover:bg-purple-200 dark:hover:bg-purple-800" data-event-id="$1">[$1]</span>')

    // Code blocks (triple backticks) - must be first to protect content
    html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, '<pre class="bg-gray-800 text-gray-100 p-3 rounded-lg overflow-x-auto my-2"><code>$2</code></pre>')

    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code class="bg-gray-200 dark:bg-gray-600 px-1 rounded text-sm">$1</code>')

    // Headers - process from h4 to h1 (most specific first)
    html = html.replace(/^#### (.+)$/gm, '<h4 class="text-base font-semibold mt-3 mb-1">$1</h4>')
    html = html.replace(/^### (.+)$/gm, '<h3 class="text-lg font-semibold mt-4 mb-2">$1</h3>')
    html = html.replace(/^## (.+)$/gm, '<h2 class="text-xl font-semibold mt-4 mb-2">$1</h2>')
    html = html.replace(/^# (.+)$/gm, '<h1 class="text-2xl font-bold mt-4 mb-2">$1</h1>')

    // Bold and italic
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>')

    // Process lists BEFORE converting newlines - match blocks of list items (allowing blank lines between)
    // Numbered lists - use \n+ to allow blank lines between items
    html = html.replace(/^(\d+\. .+(?:\n+\d+\. .+)*)/gm, (match) => {
      const items = match.split(/\n+/).map(line => {
        const m = line.match(/^\d+\. (.+)$/)
        return m ? `<li>${m[1]}</li>` : ''
      }).filter(Boolean).join('')
      return `<ol class="list-decimal my-2 pl-6 space-y-1">${items}</ol>`
    })

    // Bullet lists - use \n+ to allow blank lines between items
    html = html.replace(/^([-*] .+(?:\n+[-*] .+)*)/gm, (match) => {
      const items = match.split(/\n+/).map(line => {
        const m = line.match(/^[-*] (.+)$/)
        return m ? `<li>${m[1]}</li>` : ''
      }).filter(Boolean).join('')
      return `<ul class="list-disc my-2 pl-6 space-y-1">${items}</ul>`
    })

    // Now handle paragraphs and line breaks
    // Split by double newlines for paragraphs
    const blocks = html.split(/\n\n+/)
    html = blocks.map(block => {
      // Don't wrap already-wrapped elements
      if (block.startsWith('<h') || block.startsWith('<ul') ||
          block.startsWith('<ol') || block.startsWith('<pre') ||
          block.startsWith('<span')) {
        return block
      }
      // Convert single newlines to <br> within paragraphs
      return `<p class="mb-3">${block.replace(/\n/g, '<br>')}</p>`
    }).join('')

    return html
  }

  cleanContent(content) {
    if (!content) return ""
    // Remove the ---SOURCES--- section if present (legacy)
    return content.replace(/\n*---SOURCES---[\s\S]*$/m, "").trim()
  }

  setLoading(loading) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = loading
    }
    if (this.hasLoadingSpinnerTarget) {
      this.loadingSpinnerTarget.classList.toggle("hidden", !loading)
    }
    if (this.hasSubmitIconTarget) {
      this.submitIconTarget.classList.toggle("hidden", loading)
    }
  }

  scrollToBottom() {
    this.messageListTarget.scrollTop = this.messageListTarget.scrollHeight
  }

  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  clearChat() {
    this.messages = []
    this.currentMessageWrapper = null

    // Every message this controller appends is tagged; removing just those
    // leaves the server-rendered welcome / empty state in place. No page
    // reload, so scroll position and the rest of the page survive.
    this.messageListTarget
      .querySelectorAll("[data-chat-message]")
      .forEach((el) => el.remove())

    this.messageListTarget.scrollTop = 0
  }

  autoResize(event) {
    const textarea = event.target
    textarea.style.height = "auto"
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + "px"
  }
}
