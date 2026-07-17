# frozen_string_literal: true

module Ai
  class RatingService
    SYSTEM_PROMPT = <<~PROMPT
      You are a content relevance scoring assistant. Your task is to evaluate how relevant a piece of content is for a specific marketing channel based on the given criteria.

      You must respond with ONLY a JSON object in this exact format:
      {"score": <number 0-100>, "reason": "<brief explanation>"}

      Scoring guidelines:
      - 80-100: Highly relevant, perfect fit for the channel
      - 50-79: Moderately relevant, could be useful
      - 20-49: Low relevance, tangentially related
      - 0-19: Not relevant, should be excluded

      Be strict but fair. Consider the target audience and channel purpose carefully.
    PROMPT

    # Transient AI failures (timeouts, 5xx, occasional empty/length responses)
    # must not silently leave an event unrated for a channel — that produced the
    # "same post rated for some channels but not others" inconsistency. Retry a
    # few times with a short backoff before giving up.
    MAX_ATTEMPTS = 3
    RETRY_BACKOFF_SECONDS = 1.5

    def initialize(channel, activity_log_id: nil)
      @channel = channel
      @activity_log_id = activity_log_id
      @client = Ai::Client.new(use_case: :classification)
    end

    def full_system_prompt
      user_context = @channel.user.system_prompt
      [user_context, SYSTEM_PROMPT].compact_blank.join("\n\n--- USER CONTEXT / SCORING GUIDELINES ---\n\n")
    end

    def rate_event(event)
      return { score: 0, reason: "No criteria defined" } if @channel.prompt.blank?

      content_text = prepare_content(event)
      return { score: 0, reason: "Empty content" } if content_text.blank?

      user_message = build_user_message(content_text)

      if @activity_log_id
        DevLog.create!(
          user: @channel.user,
          log_type: :ai_request,
          message: "Rating event #{event.id} for #{@channel.name}",
          details: {
            event_id: event.id,
            content: content_text,
            system_prompt: full_system_prompt,
            user_prompt: user_message
          },
          parent_type: 'ActivityLog',
          parent_id: @activity_log_id
        )
      end

      attempt = 0
      begin
        attempt += 1
        response = @client.chat(
          messages: [
            { role: "system", content: full_system_prompt },
            { role: "user", content: user_message }
          ],
          temperature: 0.2,
          max_tokens: 1000
        )

        parsed = parse_response(response)

        # A malformed/unparseable response is transient too — surface it as an
        # ApiError so the retry path below gets a chance before we give up.
        raise Ai::Client::ApiError, parsed[:reason] if parsed[:error]

        if @activity_log_id
          DevLog.create!(
            user: @channel.user,
            log_type: :ai_response,
            message: "AI response for event #{event.id}",
            details: {
              event_id: event.id,
              raw_response: response.truncate(4000),
              parsed_score: parsed[:score],
              parsed_reason: parsed[:reason]
            },
            parent_type: 'ActivityLog',
            parent_id: @activity_log_id
          )
        end

        parsed
      rescue Ai::Client::ApiError => e
        if attempt < MAX_ATTEMPTS
          Rails.logger.warn("AI Rating attempt #{attempt}/#{MAX_ATTEMPTS} failed for event #{event.id} (#{@channel.name}): #{e.message} — retrying")
          sleep(RETRY_BACKOFF_SECONDS * attempt)
          retry
        end

        Rails.logger.error("AI Rating failed for event #{event.id} after #{MAX_ATTEMPTS} attempts: #{e.message}")
        if @activity_log_id
          DevLog.create!(
            user: @channel.user,
            log_type: :rating_error,
            message: "Rating failed: #{e.message}",
            details: { event_id: event.id, error: e.message },
            parent_type: 'ActivityLog',
            parent_id: @activity_log_id
          )
        end
        { score: nil, reason: "Rating failed: #{e.message}", error: true }
      end
    end

    def rate_events(events)
      events.map do |event|
        result = rate_event(event)
        { event: event, **result }
      end
    end

    private

    def prepare_content(event)
      parts = []

      if event.metadata["title"].present?
        parts << "Title: #{event.metadata['title']}"
      end

      parts << event.content.truncate(2000)

      if event.metadata["link"].present?
        parts << "Link: #{event.metadata['link']}"
      end

      # Include linked content summaries for additional context
      linked_context = prepare_linked_content(event)
      parts << linked_context if linked_context.present?

      parts.join("\n\n")
    end

    def prepare_linked_content(event)
      linked_contents = event.linked_contents.fetched.limit(3)
      return nil if linked_contents.empty?

      summaries = linked_contents.filter_map do |lc|
        # Skip if there was a fetch error
        next if lc.metadata&.dig("fetch_error").present?

        # Skip if content is too short to be meaningful
        next if lc.content.to_s.length < 100

        summary = lc.metadata&.dig("summary")
        title = lc.title

        # Only include if we have meaningful title or summary
        next if title.blank? && summary.blank?

        if summary.present?
          "- #{title}: #{summary}"
        else
          "- #{title}"
        end
      end

      return nil if summaries.empty?

      "Linked content:\n#{summaries.join("\n")}"
    end

    def build_user_message(content_text)
      <<~MESSAGE
        ## Channel: #{@channel.name}
        #{@channel.description.present? ? "Description: #{@channel.description}" : ""}
        Language: #{@channel.language}

        ## Relevance Criteria:
        #{@channel.prompt}

        ## Content to evaluate:
        #{content_text}

        Rate this content's relevance for the channel. Respond with JSON only.
      MESSAGE
    end

    def parse_response(response)
      # Try to extract JSON from the response
      json_match = response.match(/\{[^}]+\}/)
      return { score: nil, reason: "Invalid response format", error: true } unless json_match

      data = JSON.parse(json_match[0])
      score = data["score"].to_i.clamp(0, 100)
      reason = data["reason"].to_s.truncate(500)

      { score: score, reason: reason }
    rescue JSON::ParserError
      { score: nil, reason: "Failed to parse AI response", error: true }
    end
  end
end
