# frozen_string_literal: true

module Streams
  # The AI channel-creation chat streamed as server-sent events (chunk,
  # proposal, complete, error). Shared by ChannelAiChatController and the app
  # API.
  class ChannelProposal
    EVENT_TYPES = %w[chunk proposal complete error].freeze

    def initialize(user)
      @user = user
    end

    def call(sse, message:, history:)
      message = message.to_s.strip
      conversation_history =
        if history.is_a?(Array)
          history
        else
          begin
            JSON.parse(history.presence || "[]")
          rescue JSON::ParserError, TypeError
            :invalid
          end
        end

      if conversation_history == :invalid || !conversation_history.is_a?(Array)
        sse.error(I18n.t("channel_ai_chat.errors.invalid_history"))
        return
      end

      if message.blank?
        sse.error(I18n.t("channel_ai_chat.errors.empty_message"))
        return
      end

      Ai::ChannelProposalService.new(@user).chat_stream(message, conversation_history: conversation_history) do |event|
        sse.event(event[:type], event[:data]) if EVENT_TYPES.include?(event[:type])
      end
    rescue => e
      Rails.logger.error("Channel AI chat streaming error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      sse.error(I18n.t("channel_ai_chat.errors.unexpected"))
    end
  end
end
