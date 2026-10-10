# frozen_string_literal: true

module Api
  module V1
    # "Ask your content" (RAG chat), streamed like the web (Streams::RagChat).
    class ChatController < BaseController
      include ActionController::Live
      include SseStreaming

      requires_paid_ai kind: "chat", prompt: :question, only: :stream

      def show
        events = current_user.events
        render json: { embedded_count: events.where.not(embedding: nil).count, total_count: events.count }
      end

      def stream
        stream_sse do |sse|
          Streams::RagChat.new(current_user).call(sse, question: params[:question], history: history_param)
        end
      end

      private

      # A JSON body arrives as an array of parameters; the stream wants plain hashes.
      def history_param
        raw = params[:history]
        raw.is_a?(Array) ? raw.map { |m| m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m } : raw
      end
    end
  end
end
