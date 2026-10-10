# frozen_string_literal: true

module Api
  module V1
    # AI channel creation: the proposal chat (Streams::ChannelProposal) and
    # creating the accepted proposals (Channels::BulkCreator), as on the web.
    class ChannelAiChatController < BaseController
      include ActionController::Live
      include SseStreaming

      requires_paid_ai kind: "chat", prompt: :message, only: :stream

      def stream
        stream_sse do |sse|
          Streams::ChannelProposal.new(current_user).call(sse, message: params[:message], history: history_param)
        end
      end

      def bulk_create
        result = Channels::BulkCreator.new(current_user, channels: params[:channels], templates: params[:templates]).call
        return render_error(:unprocessable_content, "invalid", result.error) unless result.ok?

        render json: { count: result.count, notice: t("channel_ai_chat.bulk_create.notice", count: result.count) }
      end

      private

      def history_param
        raw = params[:history]
        raw.is_a?(Array) ? raw.map { |m| m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m } : raw
      end
    end
  end
end
