# frozen_string_literal: true

module Links
  class SummarizationService
    MAX_CONTENT_FOR_SUMMARY = 8000

    def initialize(linked_content)
      @linked_content = linked_content
    end

    def summarize
      return if @linked_content.content.blank?
      return if @linked_content.metadata&.dig("summary").present?

      content_for_summary = @linked_content.content.truncate(MAX_CONTENT_FOR_SUMMARY)

      summary = generate_summary(
        title: @linked_content.title,
        content: content_for_summary
      )

      return unless summary.present?

      @linked_content.update!(
        metadata: (@linked_content.metadata || {}).merge("summary" => summary)
      )

      summary
    end

    private

    def generate_summary(title:, content:)
      client = Ai::Client.new(use_case: :link_summarization)

      prompt = build_prompt(title, content)

      response = client.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        temperature: 0.3,
        max_tokens: 2000
      )

      response&.strip
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Link summarization failed: #{e.message}")
      nil
    end

    def system_prompt
      <<~PROMPT
        You are a content summarizer. Your task is to provide a brief, informative summary of web content.
        Focus on the main topic and key points. Be concise but capture the essence of the content.
        Output only the summary, no preamble or explanation.
      PROMPT
    end

    def build_prompt(title, content)
      <<~PROMPT
        Summarize this web content in 1-2 sentences (max 200 characters):

        Title: #{title}

        Content:
        #{content}
      PROMPT
    end
  end
end
