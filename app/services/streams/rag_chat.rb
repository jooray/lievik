# frozen_string_literal: true

module Streams
  # "Ask your content" streamed as server-sent events: chunk… then complete
  # with the cited events. Shared by RagChatController and the app API.
  class RagChat
    # Handle both a JSON body (already parsed array) and a query string (JSON
    # string). Anything malformed is treated as "no history" rather than a 500.
    def self.parse_history(history_param)
      history = if history_param.is_a?(Array)
        history_param
      else
        begin
          JSON.parse(history_param.presence || "[]")
        rescue JSON::ParserError, TypeError
          []
        end
      end
      history.is_a?(Array) ? history : []
    end

    def self.event_summary(event)
      {
        id: event.id,
        content: event.content.to_s.truncate(300),
        source_name: event.source&.name || I18n.t("rag_chat.unknown_source"),
        published_at: event.published_at && I18n.l(event.published_at.to_date, format: I18n.t("rag_chat.date_format"))
      }
    end

    def initialize(user)
      @user = user
    end

    def call(sse, question:, history:)
      question = question.to_s.strip
      conversation_history = self.class.parse_history(history)

      if question.blank?
        sse.error(I18n.t("rag_chat.errors.question_required"))
        return
      end

      result = Rag::ChatService.new(@user).chat_stream(question, conversation_history: conversation_history) do |chunk|
        sse.event("chunk", chunk)
      end

      cited = []
      if result[:success] && result[:cited_event_ids].present?
        # Scoped to the current user: citation ids ultimately originate from
        # client-supplied conversation history, which must never be able to
        # surface another user's content.
        cited = @user.events.where(id: result[:cited_event_ids]).includes(source: :user).map { |e| self.class.event_summary(e) }
      end
      sse.event("complete", { success: true, cited_events: cited })
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Chat streaming failed: #{e.message}")
      sse.error(e.message)
    rescue => e
      Rails.logger.error("Chat streaming error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      sse.error(I18n.t("rag_chat.errors.unexpected"))
    end
  end
end
