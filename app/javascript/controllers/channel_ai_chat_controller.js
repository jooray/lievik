import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messageList", "input", "submitButton", "loadingSpinner", "submitIcon",
    "proposalArea", "proposalContent"
  ]
  static values = {
    streamUrl: String,
    bulkCreateUrl: String,
    channelsUrl: String
  }

  connect() {
    this.messages = []
    this.isStreaming = false
    this.currentProposal = null
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.submit()
    }
  }

  autoResize(event) {
    const textarea = event.target
    textarea.style.height = "auto"
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + "px"
  }

  async submit() {
    const message = this.inputTarget.value.trim()
    if (!message || this.isStreaming) return

    this.addUserMessage(message)
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"

    this.setLoading(true)
    this.isStreaming = true

    const { contentDiv } = this.addAssistantMessage("")

    // Build conversation history
    const history = this.messages.slice(0, -1).map(m => ({
      role: m.role,
      content: m.content
    }))

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch(this.streamUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ message, history })
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

        const events = buffer.split("\n\n")
        buffer = events.pop()

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
            // Display text with JSON blocks stripped. Re-rendering the whole
            // answer per chunk is O(n^2) and visibly janky, so coalesce to one
            // render per animation frame.
            if (this.stripJsonBlocks(fullContent).trim()) {
              this.scheduleRender(contentDiv, () => this.stripJsonBlocks(fullContent))
            }
            this.scrollToBottom()
          } else if (eventType === "proposal" && eventData) {
            const proposal = JSON.parse(eventData)
            this.currentProposal = proposal
            this.renderProposal(proposal)
          } else if (eventType === "complete" && eventData) {
            this.cancelScheduledRender()
            this.isStreaming = false
            this.setLoading(false)

            // Client-side fallback: if server didn't find a proposal, try extracting here
            const completeData = JSON.parse(eventData)
            if (!completeData.has_proposal && !this.currentProposal && fullContent.includes('"channels"')) {
              const recovered = this.tryExtractProposal(fullContent)
              if (recovered) {
                console.log("Channel AI chat: recovered proposal client-side")
                this.currentProposal = recovered
                this.renderProposal(recovered)
              }
            }

            // Update stored message content (stripped of JSON)
            const lastMessage = this.messages[this.messages.length - 1]
            if (lastMessage && lastMessage.role === "assistant") {
              lastMessage.content = this.stripJsonBlocks(fullContent)
            }

            // Final render of display content
            const displayContent = this.stripJsonBlocks(fullContent)
            contentDiv.innerHTML = this.renderMarkdown(displayContent)
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

    const bubble = document.createElement("div")
    bubble.className = "flex justify-end"

    const inner = document.createElement("div")
    inner.className = "max-w-[85%] px-4 py-3 rounded-2xl bg-purple-600 text-white text-sm prose prose-sm prose-invert max-w-none"
    inner.innerHTML = this.renderMarkdown(content)

    bubble.appendChild(inner)
    this.messageListTarget.appendChild(bubble)
    this.scrollToBottom()
  }

  addAssistantMessage(content) {
    this.messages.push({ role: "assistant", content })

    const bubble = document.createElement("div")
    bubble.className = "flex justify-start"

    const inner = document.createElement("div")
    inner.className = "max-w-[85%] px-4 py-3 rounded-2xl bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100"

    const contentDiv = document.createElement("div")
    contentDiv.className = "prose prose-sm dark:prose-invert max-w-none"

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

    inner.appendChild(contentDiv)
    bubble.appendChild(inner)
    this.messageListTarget.appendChild(bubble)
    this.scrollToBottom()

    return { contentDiv }
  }

  // --- Proposal Rendering ---

  renderProposal(proposal) {
    this.proposalAreaTarget.classList.remove("hidden")

    const channels = proposal.channels || []
    const templates = proposal.templates || []

    let html = `
      <div class="space-y-4">
        <!-- Header -->
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold text-gray-900 dark:text-white">
            Proposed Channels (${channels.length})
          </h2>
          <div class="flex gap-2">
            <button type="button"
                    data-action="click->channel-ai-chat#createSelected"
                    class="inline-flex items-center px-3 py-1.5 text-xs font-medium rounded-md border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-200 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700">
              Create Selected
            </button>
            <button type="button"
                    data-action="click->channel-ai-chat#createAll"
                    class="inline-flex items-center px-3 py-1.5 text-xs font-medium rounded-md text-white bg-purple-600 hover:bg-purple-700">
              Create All
            </button>
          </div>
        </div>
    `

    // Template cards (if any)
    if (templates.length > 0) {
      html += `
        <div class="space-y-2">
          <h3 class="text-sm font-medium text-gray-600 dark:text-gray-400">New Templates</h3>
          ${templates.map((t, i) => this.renderTemplateCard(t, i)).join("")}
        </div>
      `
    }

    // Channel cards
    html += `<div class="space-y-3" data-channel-ai-chat-target="channelCards">`
    channels.forEach((channel, index) => {
      html += this.renderChannelCard(channel, index)
    })
    html += `</div></div>`

    this.proposalContentTarget.innerHTML = html
  }

  renderChannelCard(channel, index) {
    const langUpper = this.escapeHtml((channel.language || "en").toUpperCase())
    // AI-supplied, and interpolated straight into a value="" attribute below —
    // coerce to a plain bounded integer so it can never carry markup.
    const parsedThreshold = parseInt(channel.settings?.relevance_threshold, 10)
    const threshold = Number.isFinite(parsedThreshold)
      ? Math.min(100, Math.max(0, parsedThreshold))
      : 50

    return `
      <div class="bg-white dark:bg-gray-800 shadow rounded-lg p-4 border border-gray-200 dark:border-gray-700"
           data-channel-index="${index}">
        <!-- Top row: checkbox, name, language badge, actions -->
        <div class="flex items-start gap-3">
          <input type="checkbox" checked
                 class="mt-1 h-4 w-4 rounded border-gray-300 text-purple-600 focus:ring-purple-500"
                 data-channel-checkbox>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span contenteditable="true"
                    class="text-base font-medium text-gray-900 dark:text-white outline-none focus:ring-1 focus:ring-purple-500 rounded px-1 -mx-1"
                    data-channel-name>${this.escapeHtml(channel.name)}</span>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 flex-shrink-0">
                ${langUpper}
              </span>
            </div>
            <div contenteditable="true"
                 class="mt-1 text-sm text-gray-500 dark:text-gray-400 outline-none focus:ring-1 focus:ring-purple-500 rounded px-1 -mx-1"
                 data-channel-description>${this.escapeHtml(channel.description || "No description")}</div>
          </div>
          <div class="flex items-center gap-1 flex-shrink-0">
            <button type="button"
                    class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                    data-action="click->channel-ai-chat#toggleCardExpand"
                    data-expand-button>
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
              </svg>
            </button>
            <button type="button"
                    class="p-1 text-gray-400 hover:text-red-500"
                    data-action="click->channel-ai-chat#removeCard">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
        </div>

        <!-- Meta row -->
        <div class="mt-2 flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400">
          ${channel.suggested_template ? `<span class="inline-flex items-center gap-1"><svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>${this.escapeHtml(channel.suggested_template)}</span>` : ""}
          <span>Threshold: ${threshold}</span>
          ${channel.content_style ? `<span>Style: ${this.escapeHtml(channel.content_style)}</span>` : ""}
        </div>

        <!-- Expandable details -->
        <div class="hidden mt-3 pt-3 border-t border-gray-200 dark:border-gray-700 space-y-3" data-expand-section>
          <div>
            <label class="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">Language</label>
            <select class="block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-sm py-1"
                    data-channel-language>
              ${this.languageOptions(channel.language)}
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">Content Style</label>
            <input type="text"
                   class="block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-sm py-1"
                   value="${this.escapeAttr(channel.content_style || "")}"
                   data-channel-style>
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">Relevance Threshold</label>
            <input type="number" min="0" max="100"
                   class="block w-24 rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-sm py-1"
                   value="${threshold}"
                   data-channel-threshold>
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1">Relevance Criteria</label>
            <textarea rows="8"
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-sm py-1 font-mono"
                      data-channel-prompt>${this.escapeHtml(channel.prompt || "")}</textarea>
          </div>
        </div>
      </div>
    `
  }

  renderTemplateCard(template, index) {
    return `
      <div class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3 border border-blue-200 dark:border-blue-800"
           data-template-index="${index}">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <input type="checkbox" checked
                   class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                   data-template-checkbox>
            <span class="text-sm font-medium text-blue-900 dark:text-blue-200"
                  contenteditable="true"
                  data-template-name>${this.escapeHtml(template.name)}</span>
          </div>
          <button type="button"
                  class="p-1 text-gray-400 hover:text-red-500"
                  data-action="click->channel-ai-chat#removeTemplateCard">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
        <textarea rows="3" class="hidden mt-2 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-xs font-mono"
                  data-template-content>${this.escapeHtml(template.template || "")}</textarea>
      </div>
    `
  }

  languageOptions(selected) {
    const langs = [
      ["en", "English"], ["sk", "Slovak"], ["cs", "Czech"],
      ["de", "German"], ["es", "Spanish"], ["fr", "French"],
      ["pt", "Portuguese"], ["it", "Italian"], ["pl", "Polish"],
      ["uk", "Ukrainian"], ["nl", "Dutch"], ["hu", "Hungarian"]
    ]
    return langs.map(([code, name]) =>
      `<option value="${code}" ${code === selected ? "selected" : ""}>${name} (${code})</option>`
    ).join("")
  }

  // --- Card Actions ---

  toggleCardExpand(event) {
    const card = event.target.closest("[data-channel-index]")
    const section = card.querySelector("[data-expand-section]")
    const button = card.querySelector("[data-expand-button]")
    const svg = button.querySelector("svg")

    section.classList.toggle("hidden")
    svg.style.transform = section.classList.contains("hidden") ? "" : "rotate(180deg)"
  }

  removeCard(event) {
    const card = event.target.closest("[data-channel-index]")
    card.remove()
    this.updateProposalCount()
  }

  removeTemplateCard(event) {
    const card = event.target.closest("[data-template-index]")
    card.remove()
  }

  updateProposalCount() {
    const cards = this.proposalContentTarget.querySelectorAll("[data-channel-index]")
    const header = this.proposalContentTarget.querySelector("h2")
    if (header) {
      header.textContent = `Proposed Channels (${cards.length})`
    }
    if (cards.length === 0) {
      this.proposalAreaTarget.classList.add("hidden")
    }
  }

  // --- Bulk Create ---

  collectChannelData(onlySelected = false) {
    const cards = this.proposalContentTarget.querySelectorAll("[data-channel-index]")
    const channels = []

    cards.forEach(card => {
      const checkbox = card.querySelector("[data-channel-checkbox]")
      if (onlySelected && !checkbox.checked) return

      const name = card.querySelector("[data-channel-name]")?.textContent?.trim()
      const description = card.querySelector("[data-channel-description]")?.textContent?.trim()
      const language = card.querySelector("[data-channel-language]")?.value ||
                       this.currentProposal?.channels?.[card.dataset.channelIndex]?.language || "en"
      const style = card.querySelector("[data-channel-style]")?.value || ""
      const threshold = parseInt(card.querySelector("[data-channel-threshold]")?.value || "50", 10)
      const prompt = card.querySelector("[data-channel-prompt]")?.value ||
                     this.currentProposal?.channels?.[card.dataset.channelIndex]?.prompt || ""

      if (name) {
        channels.push({
          name, description, language, prompt,
          content_style: style,
          content_language: language,
          settings: { relevance_threshold: threshold, humanize_output: true }
        })
      }
    })

    return channels
  }

  collectTemplateData() {
    const cards = this.proposalContentTarget.querySelectorAll("[data-template-index]")
    const templates = []

    cards.forEach(card => {
      const checkbox = card.querySelector("[data-template-checkbox]")
      if (!checkbox.checked) return

      const name = card.querySelector("[data-template-name]")?.textContent?.trim()
      const content = card.querySelector("[data-template-content]")?.value?.trim()

      if (name && content) {
        templates.push({ name, template: content })
      }
    })

    return templates
  }

  async createAll() {
    await this.submitBulkCreate(false)
  }

  async createSelected() {
    await this.submitBulkCreate(true)
  }

  async submitBulkCreate(onlySelected) {
    const channels = this.collectChannelData(onlySelected)
    const templates = this.collectTemplateData()

    if (channels.length === 0) {
      alert("No channels selected to create.")
      return
    }

    // Disable buttons during creation
    const buttons = this.proposalContentTarget.querySelectorAll("button")
    buttons.forEach(b => b.disabled = true)

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch(this.bulkCreateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ channels, templates })
      })

      const data = await response.json()

      if (data.success) {
        // Show success message in chat
        this.addAssistantSuccessMessage(
          `Created ${data.count} channel${data.count === 1 ? '' : 's'}! Redirecting to channels...`
        )
        // Redirect after a brief delay
        setTimeout(() => {
          window.location.href = data.redirect_to || this.channelsUrlValue
        }, 1500)
      } else {
        alert(`Failed to create channels: ${data.error}`)
        buttons.forEach(b => b.disabled = false)
      }
    } catch (error) {
      alert(`Error: ${error.message}`)
      buttons.forEach(b => b.disabled = false)
    }
  }

  addAssistantSuccessMessage(text) {
    const bubble = document.createElement("div")
    bubble.className = "flex justify-start"

    const inner = document.createElement("div")
    inner.className = "max-w-[85%] px-4 py-3 rounded-2xl bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 text-sm font-medium"
    inner.textContent = text

    bubble.appendChild(inner)
    this.messageListTarget.appendChild(bubble)
    this.scrollToBottom()
  }

  // --- Utilities ---

  stripJsonBlocks(content) {
    if (!content) return ""
    // Flexible: newlines around fences are optional
    return content.replace(/```json\s*\n?[\s\S]*?\n?\s*```/g, "").trim()
  }

  tryExtractProposal(content) {
    // Try fenced block first
    const fenceMatch = content.match(/```json\s*\n?([\s\S]*?)\n?\s*```/)
    if (fenceMatch) {
      try {
        const proposal = JSON.parse(fenceMatch[1])
        if (proposal?.channels?.length > 0) return proposal
      } catch (e) { /* fall through */ }
    }

    // Fallback: brace-counting from {"channels" (or pretty-printed variant)
    let startIdx = content.indexOf('{"channels"')
    if (startIdx === -1) {
      const match = content.match(/\{\s*"channels"/)
      if (match) startIdx = match.index
    }
    if (startIdx === -1) return null

    let depth = 0
    for (let i = startIdx; i < content.length; i++) {
      const ch = content[i]
      if (ch === "{") depth++
      else if (ch === "}") {
        depth--
        if (depth === 0) {
          try {
            const proposal = JSON.parse(content.substring(startIdx, i + 1))
            if (proposal?.channels?.length > 0) return proposal
          } catch (e) { return null }
        }
      } else if (ch === '"') {
        i++
        while (i < content.length) {
          if (content[i] === "\\") i++
          else if (content[i] === '"') break
          i++
        }
      }
    }
    return null
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
    let html = content

    // Code blocks (triple backticks)
    html = html.replace(/```(\w*)\n?([\s\S]*?)```/g,
      '<pre class="bg-gray-800 text-gray-100 p-3 rounded-lg overflow-x-auto my-2"><code>$2</code></pre>')

    // Inline code
    html = html.replace(/`([^`]+)`/g,
      '<code class="bg-gray-200 dark:bg-gray-600 px-1 rounded text-sm">$1</code>')

    // Headers
    html = html.replace(/^#### (.+)$/gm, '<h4 class="text-base font-semibold mt-3 mb-1">$1</h4>')
    html = html.replace(/^### (.+)$/gm, '<h3 class="text-lg font-semibold mt-4 mb-2">$1</h3>')
    html = html.replace(/^## (.+)$/gm, '<h2 class="text-xl font-semibold mt-4 mb-2">$1</h2>')
    html = html.replace(/^# (.+)$/gm, '<h1 class="text-2xl font-bold mt-4 mb-2">$1</h1>')

    // Bold and italic
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>')

    // Numbered lists
    html = html.replace(/^(\d+\. .+(?:\n+\d+\. .+)*)/gm, (match) => {
      const items = match.split(/\n+/).map(line => {
        const m = line.match(/^\d+\. (.+)$/)
        return m ? `<li>${m[1]}</li>` : ''
      }).filter(Boolean).join('')
      return `<ol class="list-decimal my-2 pl-6 space-y-1">${items}</ol>`
    })

    // Bullet lists
    html = html.replace(/^([-*] .+(?:\n+[-*] .+)*)/gm, (match) => {
      const items = match.split(/\n+/).map(line => {
        const m = line.match(/^[-*] (.+)$/)
        return m ? `<li>${m[1]}</li>` : ''
      }).filter(Boolean).join('')
      return `<ul class="list-disc my-2 pl-6 space-y-1">${items}</ul>`
    })

    // Paragraphs
    const blocks = html.split(/\n\n+/)
    html = blocks.map(block => {
      if (block.startsWith('<h') || block.startsWith('<ul') ||
          block.startsWith('<ol') || block.startsWith('<pre')) {
        return block
      }
      return `<p class="mb-3">${block.replace(/\n/g, '<br>')}</p>`
    }).join('')

    return html
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

  escapeAttr(text) {
    if (!text) return ""
    return text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  clearChat() {
    window.location.reload()
  }
}
