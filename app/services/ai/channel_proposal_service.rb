# frozen_string_literal: true

module Ai
  class ChannelProposalService
    # Flexible fence regex: newlines around fences are optional
    PROPOSAL_REGEX = /```json\s*\n?(.*?)\n?\s*```/m

    def initialize(user)
      @user = user
      @skill = Ai::SkillLoader.load("channel_proposer")
      @client = Ai::Client.new(use_case: :channel_proposal)
    end

    # Streams the AI response, yielding SSE events
    # Yields: { type: "chunk", data: "text" }
    #         { type: "proposal", data: { channels: [...], templates: [...] } }
    #         { type: "complete", data: { has_proposal: true/false } }
    #         { type: "error", data: { message: "..." } }
    def chat_stream(message, conversation_history: [], &block)
      messages = build_messages(message, conversation_history)
      full_response = ""

      @client.chat_stream(
        messages: messages,
        temperature: @skill[:temperature],
        max_tokens: @skill[:max_tokens]
      ) do |chunk|
        full_response += chunk
        yield({ type: "chunk", data: chunk })
      end

      # Extract and validate proposal from complete response
      proposal = extract_proposal(full_response)
      if proposal
        yield({ type: "proposal", data: proposal })
      end

      yield({ type: "complete", data: { has_proposal: proposal.present? } })

      { success: true, response: full_response, proposal: proposal }
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Channel proposal streaming failed: #{e.message}")
      yield({ type: "error", data: { message: e.message } })
      { success: false, error: e.message }
    rescue => e
      Rails.logger.error("Channel proposal error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      yield({ type: "error", data: { message: "An unexpected error occurred" } })
      { success: false, error: e.message }
    end

    private

    def build_messages(message, conversation_history)
      system_prompt = build_system_prompt

      messages = [{ role: "system", content: system_prompt }]

      # Add conversation history
      conversation_history.each do |msg|
        messages << { role: msg["role"] || msg[:role], content: msg["content"] || msg[:content] }
      end

      # Add current message
      messages << { role: "user", content: message }

      messages
    end

    def build_system_prompt
      parts = [@skill[:prompt]]

      # Add existing channels context
      existing_channels = @user.channels.order(:name)
      if existing_channels.any?
        channel_list = existing_channels.map { |c| "- #{c.name} (#{c.language}): #{c.description}" }.join("\n")
        parts << "\n## User's Existing Channels\n\n#{channel_list}"
      end

      # Add available templates
      templates = @user.content_templates_list
      if templates.any?
        template_list = templates.map { |t| "- #{t['name']}" }.join("\n")
        parts << "\n## Available Content Templates\n\n#{template_list}"
      else
        default_templates = User::DEFAULT_CONTENT_TEMPLATES.map { |t| "- #{t['name']}" }.join("\n")
        parts << "\n## Available Content Templates (defaults)\n\n#{default_templates}"
      end

      # Add available languages hint
      parts << "\n## Common Languages\n\nen (English), sk (Slovak), cs (Czech), de (German), es (Spanish), fr (French), pt (Portuguese), it (Italian), pl (Polish), uk (Ukrainian)"

      parts.join("\n")
    end

    def extract_proposal(response)
      json_str = extract_json_string(response)
      return nil unless json_str

      proposal = JSON.parse(json_str)

      # Validate basic structure
      return nil unless proposal.is_a?(Hash)
      return nil unless proposal["channels"].is_a?(Array) && proposal["channels"].any?

      # Validate each channel has required fields
      proposal["channels"].each do |channel|
        return nil unless channel["name"].present? && channel["language"].present?
      end

      proposal
    rescue JSON::ParserError => e
      Rails.logger.warn("Failed to parse channel proposal JSON: #{e.message}")
      Rails.logger.warn("Response tail (500 chars): #{response.last(500)}")
      nil
    end

    def extract_json_string(response)
      # Strategy 1: Flexible fenced code block regex
      match = response.match(PROPOSAL_REGEX)
      if match
        Rails.logger.info("Channel proposal: extracted JSON via fenced code block")
        return match[1]
      end

      # Strategy 2: Brace-counting fallback — find {"channels" and match closing brace
      # Handle both compact '{"channels"' and pretty-printed '{\n  "channels"'
      start_idx = response.index('{"channels"')
      start_idx ||= response.index(/\{\s*"channels"/)
      if start_idx
        json_str = extract_balanced_json(response, start_idx)
        if json_str
          Rails.logger.info("Channel proposal: extracted JSON via brace-counting fallback")
          return json_str
        end
      end

      Rails.logger.warn("Channel proposal: failed to extract JSON from response")
      Rails.logger.warn("Response tail (500 chars): #{response.last(500)}")
      nil
    end

    def extract_balanced_json(text, start_idx)
      depth = 0
      i = start_idx

      while i < text.length
        char = text[i]
        if char == "{"
          depth += 1
        elsif char == "}"
          depth -= 1
          if depth == 0
            return text[start_idx..i]
          end
        elsif char == '"'
          # Skip string contents (handle escaped quotes)
          i += 1
          while i < text.length
            if text[i] == '\\'
              i += 1 # skip escaped character
            elsif text[i] == '"'
              break
            end
            i += 1
          end
        end
        i += 1
      end

      nil
    end
  end
end
