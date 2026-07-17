# frozen_string_literal: true

module Ai
  class ContentBuilderService
    SYSTEM_PROMPT = <<~PROMPT
      You are a professional content writer and editor. Your task is to create well-formatted, engaging content based on source material and channel guidelines.

      Guidelines:
      - Follow the formatting instructions precisely
      - Maintain the specified writing style and tone
      - Write in the specified language
      - Use markdown formatting appropriately
      - Create content that is cohesive and flows naturally
      - Extract key insights from the source material
      - Do not fabricate information not present in the sources
    PROMPT

    REFINE_SYSTEM_PROMPT = <<~PROMPT
      You are a professional content editor. Your task is to refine and improve existing content based on user feedback while maintaining the original meaning and staying true to the source material.

      Guidelines:
      - Apply the user's requested changes
      - Maintain consistency with the channel's style guidelines
      - Keep the content accurate to the source material
      - Return the complete updated content (not just the changes)
      - Use markdown formatting appropriately
    PROMPT

    def initialize(channel:, events:, activity_log_id: nil, title: nil, generation_prompt: nil)
      @channel = channel
      @events = events
      @activity_log_id = activity_log_id
      @title = title
      @generation_prompt = generation_prompt
      @generation_client = Ai::Client.new(use_case: :content_generation)
      @refinement_client = Ai::Client.new(use_case: :content_refinement)
      @humanization_client = Ai::Client.new(use_case: :content_humanization)
    end

    def generate
      return { content: "", error: "No events provided" } if @events.empty?

      user_message = build_generate_prompt

      log_request("Generating content for #{@channel.name}", user_message, full_system_prompt)

      begin
        response = request_generation(@generation_client, user_message)

        if generation_looks_incomplete?(response)
          continuation = continue_generation(response, streaming: false)
          response = [response, continuation].join if continuation.present?
        end

        log_response(response)

        { content: post_process_content(response), error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content generation failed: #{e.message}")
        log_error(e.message)
        { content: nil, error: e.message }
      end
    end

    # Post-process content: strip markdown fences and replace nostr: URIs
    def post_process_content(content)
      return content if content.blank?

      result = strip_markdown_fences(content.strip)
      replace_nostr_uris(result)
    end

    def generate_stream(&block)
      return { error: "No events provided" } if @events.empty?

      user_message = build_generate_prompt

      log_request("Generating content (streaming) for #{@channel.name}", user_message, full_system_prompt)

      begin
        full_content = stream_generation(user_message, &block)
        Rails.logger.info("Generation stream length after first pass: #{full_content.length}")

        if generation_looks_incomplete?(full_content)
          Rails.logger.warn("Generation looked incomplete, requesting continuation")
          continuation = continue_generation(full_content, streaming: true, &block)
          full_content += continuation if continuation.present?
          Rails.logger.info("Generation stream length after continuation: #{full_content.length}")
        end

        if full_content.strip.blank?
          log_error("No content in streaming response")
          return { content: nil, error: "No content in AI response" }
        end

        log_response(full_content)

        { content: full_content.strip, error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content generation failed: #{e.message}")
        log_error(e.message)
        { content: nil, error: e.message }
      end
    end

    def refine(existing_content:, user_prompt:)
      return { content: "", error: "No content to refine" } if existing_content.blank?
      return { content: existing_content, error: "No instructions provided" } if user_prompt.blank?

      user_message = build_refine_prompt(existing_content, user_prompt)

      log_request("Refining content for #{@channel.name}: #{user_prompt.truncate(50)}", user_message, refine_system_prompt)

      begin
        response = @refinement_client.chat(
          messages: [
            { role: "system", content: refine_system_prompt },
            { role: "user", content: user_message }
          ],
          temperature: 0.7,
          max_tokens: 4000
        )

        log_response(response)

        { content: post_process_content(response), error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content refinement failed: #{e.message}")
        log_error(e.message)
        { content: nil, error: e.message }
      end
    end

    def refine_stream(existing_content:, user_prompt:, &block)
      return { error: "No content to refine" } if existing_content.blank?
      return { error: "No instructions provided" } if user_prompt.blank?

      user_message = build_refine_prompt(existing_content, user_prompt)

      log_request("Refining content (streaming) for #{@channel.name}: #{user_prompt.truncate(50)}", user_message, refine_system_prompt)

      begin
        full_content = ""
        @refinement_client.chat_stream(
          messages: [
            { role: "system", content: refine_system_prompt },
            { role: "user", content: user_message }
          ],
          temperature: 0.7,
          max_tokens: 4000
        ) do |chunk|
          full_content += chunk
          yield chunk
        end

        if full_content.strip.blank?
          log_error("No content in streaming response")
          return { content: nil, error: "No content in AI response" }
        end

        log_response(full_content)

        { content: full_content.strip, error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content refinement failed: #{e.message}")
        log_error(e.message)
        { content: nil, error: e.message }
      end
    end

    def humanize(content)
      return { content: content, error: nil } if content.blank?

      skill = load_humanizer_skill
      unless skill
        Rails.logger.warn("Humanizer skill not available, returning original content")
        return { content: content, error: nil }
      end

      user_message = build_humanize_prompt(content, @channel.effective_content_language)

      log_request("Humanizing content for #{@channel.name}", user_message, skill[:prompt])

      begin
        response = @humanization_client.chat(
          messages: [
            { role: "system", content: skill[:prompt] },
            { role: "user", content: user_message }
          ],
          temperature: skill[:temperature],
          max_tokens: skill[:max_tokens]
        )

        log_response(response)

        { content: post_process_content(response), error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content humanization failed: #{e.message}")
        log_error(e.message)
        # Return original content on error - humanization failure should not fail the operation
        { content: content, error: nil }
      end
    end

    def humanize_stream(content, &block)
      if content.blank?
        yield content if block_given?
        return { content: content, error: nil }
      end

      skill = load_humanizer_skill
      unless skill
        Rails.logger.warn("Humanizer skill not available, returning original content")
        yield content if block_given?
        return { content: content, error: nil }
      end

      user_message = build_humanize_prompt(content, @channel.effective_content_language)

      log_request("Humanizing content (streaming) for #{@channel.name}", user_message, skill[:prompt])

      begin
        full_content = ""
        @humanization_client.chat_stream(
          messages: [
            { role: "system", content: skill[:prompt] },
            { role: "user", content: user_message }
          ],
          temperature: skill[:temperature],
          max_tokens: skill[:max_tokens]
        ) do |chunk|
          full_content += chunk
          yield chunk
        end

        if full_content.strip.blank?
          log_error("No content in streaming response")
          yield content if block_given?
          return { content: content, error: nil }
        end

        log_response(full_content)

        { content: full_content.strip, error: nil }
      rescue Ai::Client::ApiError => e
        Rails.logger.error("Content humanization failed: #{e.message}")
        log_error(e.message)
        # Return original content on error - humanization failure should not fail the operation
        yield content if block_given?
        { content: content, error: nil }
      end
    end

    def humanize_enabled?
      @channel.humanize_output?
    end

    private

    def load_humanizer_skill
      Ai::SkillLoader.load("humanizer")
    rescue Ai::SkillLoader::SkillNotFoundError, Ai::SkillLoader::SkillParseError => e
      Rails.logger.warn("Failed to load humanizer skill: #{e.message}")
      nil
    end

    def build_humanize_prompt(content, language)
      <<~PROMPT
        The following content is in **#{language}**. You MUST keep the output in #{language}.
        Do NOT translate. Output must be in the same language as the input.

        ---

        #{content}
      PROMPT
    end

    def full_system_prompt
      user_context = @channel.user.system_prompt
      [user_context, SYSTEM_PROMPT].compact_blank.join("\n\n--- USER CONTEXT ---\n\n")
    end

    def refine_system_prompt
      user_context = @channel.user.system_prompt
      [user_context, REFINE_SYSTEM_PROMPT].compact_blank.join("\n\n--- USER CONTEXT ---\n\n")
    end

    def build_generate_prompt
      parts = []

      # Channel context
      parts << "## Channel Information"
      parts << "**Channel:** #{@channel.name}"
      parts << "**Purpose:** #{@channel.description}" if @channel.description.present?
      parts << "**Target Language:** #{@channel.effective_content_language}"
      parts << "**Writing Style:** #{@channel.content_style}" if @channel.content_style.present?
      parts << ""

      # Content title if provided
      if @title.present?
        parts << "## Content Title"
        parts << "The user has specified the following title for this content: **#{@title}**"
        parts << "Use this title as the main heading and ensure the content supports this theme."
        parts << ""
      end

      # User's generation prompt / theme direction
      if @generation_prompt.present?
        parts << "## Theme / Direction"
        parts << "The user has provided the following guidance for this content:"
        parts << @generation_prompt
        parts << ""
      end

      # Content formatting instructions
      if @channel.content_prompt.present?
        parts << "## Content Formatting Instructions"
        parts << @channel.content_prompt
        parts << ""
      end

      # Source material
      parts << "## Source Material"
      parts << "Create content based on the following #{@events.size} source events:"
      parts << ""

      @events.each_with_index do |event, index|
        parts << "### Source #{index + 1}"
        parts << "**From:** #{event.source.name}"
        parts << "**Date:** #{event.published_at.strftime('%Y-%m-%d')}"

        # Include source reference link (nevent for Nostr, URL for RSS)
        source_link = event.source_link(@channel.user)
        if source_link.present?
          parts << "**Source Link:** #{source_link}"
        end

        parts << "**Content:**"
        parts << event.content
        parts << ""

        # Include linked content if available
        if event.linked_contents.any?
          event.linked_contents.each do |link|
            parts << "**Linked Content (#{link.url}):**"

            if link.title.present?
              parts << "Title: #{link.title}"
            end

            summary = link.metadata&.dig("summary")
            if summary.present?
              parts << "Summary: #{summary}"
            elsif link.content.present?
              parts << "Excerpt: #{link.content.to_s.truncate(2000)}"
            end

            parts << ""
          end
        end
      end

      parts << "---"
      parts << "Now create the formatted content following the instructions above."

      parts.join("\n")
    end

    def build_refine_prompt(existing_content, user_prompt)
      parts = []

      # Channel context
      parts << "## Channel Information"
      parts << "**Channel:** #{@channel.name}"
      parts << "**Target Language:** #{@channel.effective_content_language}"
      parts << "**Writing Style:** #{@channel.content_style}" if @channel.content_style.present?
      parts << ""

      # Original sources for reference
      parts << "## Original Source Material (for reference)"
      @events.each_with_index do |event, index|
        parts << "### Source #{index + 1}: #{event.source.name}"
        parts << event.content.truncate(500)
        parts << ""
      end

      # Current content
      parts << "## Current Content to Edit"
      parts << "```markdown"
      parts << existing_content
      parts << "```"
      parts << ""

      # User's edit request
      parts << "## Edit Instructions"
      parts << user_prompt
      parts << ""

      parts << "---"
      parts << "Apply the edit instructions and return the complete updated content."

      parts.join("\n")
    end

    def generation_messages(user_message)
      [
        { role: "system", content: full_system_prompt },
        { role: "user", content: user_message }
      ]
    end

    def request_generation(client, user_message)
      client.chat(
        messages: generation_messages(user_message),
        temperature: 0.7,
        max_tokens: 4000
      )
    end

    def stream_generation(user_message, &block)
      full_content = ""

      @generation_client.chat_stream(
        messages: generation_messages(user_message),
        temperature: 0.7,
        max_tokens: 4000
      ) do |chunk|
        full_content += chunk
        yield chunk if block_given?
      end

      full_content
    end

    def continue_generation(existing_content, streaming:, &block)
      prompt = build_continue_generation_prompt(existing_content)

      log_request("Continuing generation for #{@channel.name}", prompt, full_system_prompt)

      if streaming
        continuation = ""
        @generation_client.chat_stream(
          messages: generation_messages(prompt),
          temperature: 0.4,
          max_tokens: 2500
        ) do |chunk|
          continuation += chunk
          yield chunk if block_given?
        end
        continuation
      else
        @generation_client.chat(
          messages: generation_messages(prompt),
          temperature: 0.4,
          max_tokens: 2500
        )
      end
    end

    def build_continue_generation_prompt(existing_content)
      <<~PROMPT
        The previously generated content stopped before it was finished.

        Continue from exactly where it ended. Do not restart, do not repeat earlier sections, and do not add an introduction.
        Return only the missing continuation in the same language, tone, and markdown structure.

        ## Existing partial content
        #{existing_content}
      PROMPT
    end

    def generation_looks_incomplete?(content)
      return false if content.blank?

      trimmed = content.rstrip
      return true if trimmed.match?(/(^|\n)#+\s+[^\n]{0,80}\z/)
      return false if trimmed.end_with?(".", "!", "?", '"', "'", "`", ")", "]")

      trimmed.length >= 1200
    end

    def log_request(message, user_prompt, system_prompt = nil)
      DevLog.create!(
        user: @channel.user,
        log_type: :ai_request,
        message: message,
        details: {
          channel_id: @channel.id,
          event_count: @events.size,
          system_prompt: system_prompt,
          user_prompt: user_prompt
        },
        parent_type: @activity_log_id ? "ActivityLog" : nil,
        parent_id: @activity_log_id
      )
    end

    def log_response(response)
      DevLog.create!(
        user: @channel.user,
        log_type: :ai_response,
        message: "Content generated successfully",
        details: {
          response_length: response.length,
          response: response
        },
        parent_type: @activity_log_id ? "ActivityLog" : nil,
        parent_id: @activity_log_id
      )
    end

    def log_error(error_message)
      DevLog.create!(
        user: @channel.user,
        log_type: :content_error,
        message: "Content generation failed: #{error_message}",
        details: { error: error_message },
        parent_type: @activity_log_id ? "ActivityLog" : nil,
        parent_id: @activity_log_id
      )
    end

    # Replace nostr: URIs with web links using the user's link templates
    # Handles note1, nevent1, naddr1 formats
    # Prefers nevent1 > note1 > hex for event identifiers
    def replace_nostr_uris(content)
      return content if content.blank?

      user = @channel.user
      event_template = user.event_link_template
      naddr_template = user.naddr_link_template

      # Match nostr: URIs (note1, nevent1, naddr1, or hex)
      content.gsub(/nostr:(note1[a-z0-9]+|nevent1[a-z0-9]+|naddr1[a-z0-9]+|[0-9a-f]{64})/i) do |match|
        identifier = match.sub(/\Anostr:/i, "")
        parsed = Nostr::KeyConverter.parse_nostr_identifier(identifier)

        if parsed.nil?
          match # Return original if can't parse
        elsif parsed[:type] == :naddr
          # For naddr, use the naddr template with the full naddr identifier
          naddr_template.gsub("{naddr}", identifier)
        elsif parsed[:type] == :nevent
          # Already have nevent, use it directly
          event_template.gsub("{eventid}", identifier)
        elsif parsed[:type] == :note
          # note1 - try to convert to nevent if we have the event in our DB with relay info
          event = find_event_by_hex(parsed[:event_id])
          if event&.nevent_id.present?
            event_template.gsub("{eventid}", event.nevent_id)
          else
            # Keep as note1 (not hex)
            event_template.gsub("{eventid}", identifier)
          end
        elsif parsed[:type] == :hex && parsed[:event_id].present?
          # Raw hex - try to convert to nevent, fallback to note1
          event = find_event_by_hex(parsed[:event_id])
          if event&.nevent_id.present?
            event_template.gsub("{eventid}", event.nevent_id)
          else
            # Convert hex to note1 (better than hex)
            note_id = Nostr::KeyConverter.hex_to_note(parsed[:event_id])
            event_template.gsub("{eventid}", note_id || parsed[:event_id])
          end
        else
          match # Return original if no event ID
        end
      end
    end

    # Try to find an event in our database by hex ID
    def find_event_by_hex(hex_event_id)
      return nil if hex_event_id.blank?

      Event.find_by(external_id: hex_event_id)
    end

    # Strip markdown code fences from the beginning and end of AI responses
    # Only strips if the response starts with ```markdown or ``` and ends with ```
    def strip_markdown_fences(content)
      return content if content.blank?

      result = content.dup

      # Strip opening fence (```markdown or ```) at the very beginning
      if result.start_with?("```markdown\n")
        result = result.sub(/\A```markdown\n/, "")
      elsif result.start_with?("```markdown\r\n")
        result = result.sub(/\A```markdown\r\n/, "")
      elsif result.start_with?("```\n")
        result = result.sub(/\A```\n/, "")
      elsif result.start_with?("```\r\n")
        result = result.sub(/\A```\r\n/, "")
      end

      # Strip closing fence at the very end
      if result.end_with?("\n```")
        result = result.sub(/\n```\z/, "")
      elsif result.end_with?("\r\n```")
        result = result.sub(/\r\n```\z/, "")
      elsif result.end_with?("```")
        result = result.sub(/```\z/, "")
      end

      result.strip
    end
  end
end
