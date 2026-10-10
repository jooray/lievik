# frozen_string_literal: true

class RagChatController < ApplicationController
  include ActionController::Live
  include SseStreaming

  requires_paid_ai kind: "chat", prompt: :question, only: [:ask, :ask_stream]

  def index
    @embedded_count = Event.joins(source: :user)
                           .where(sources: { user_id: current_user.id })
                           .where.not(embedding: nil)
                           .count
    @total_count = Event.joins(source: :user)
                        .where(sources: { user_id: current_user.id })
                        .count
  end

  def ask
    question = params[:question].to_s.strip
    conversation_history = params[:history] || []

    if question.blank?
      render json: { success: false, error: t("rag_chat.errors.question_required") }
      return
    end

    chat_service = Rag::ChatService.new(current_user)
    result = chat_service.chat(question, conversation_history: conversation_history)

    if result[:success]
      render json: {
        success: true,
        answer: result[:answer],
        cited_events: result[:cited_events].map { |e| event_summary(e) },
        context_count: result[:context_event_ids].size
      }
    else
      render json: { success: false, error: result[:error] }
    end
  end

  def ask_stream
    stream_sse do |sse|
      Streams::RagChat.new(current_user).call(sse, question: params[:question], history: params[:history])
    end
  end

  private

  def event_summary(event)
    Streams::RagChat.event_summary(event)
  end
end
