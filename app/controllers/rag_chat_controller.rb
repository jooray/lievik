# frozen_string_literal: true

class RagChatController < ApplicationController
  include ActionController::Live

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
      render json: { success: false, error: "Please enter a question" }
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
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    question = params[:question].to_s.strip
    # Handle both JSON body (already parsed array) and query string (JSON string)
    history_param = params[:history]
    conversation_history = history_param.is_a?(Array) ? history_param : JSON.parse(history_param || "[]")

    if question.blank?
      response.stream.write "event: error\ndata: #{({ message: "Please enter a question" }).to_json}\n\n"
      response.stream.close
      return
    end

    chat_service = Rag::ChatService.new(current_user)

    begin
      result = chat_service.chat_stream(question, conversation_history: conversation_history) do |chunk|
        escaped_chunk = chunk.to_json
        response.stream.write "event: chunk\ndata: #{escaped_chunk}\n\n"
      end

      # Send cited events on completion
      if result[:success] && result[:cited_event_ids].present?
        cited_events = Event.where(id: result[:cited_event_ids]).includes(source: :user)
        response.stream.write "event: complete\ndata: #{({ success: true, cited_events: cited_events.map { |e| event_summary(e) } }).to_json}\n\n"
      else
        response.stream.write "event: complete\ndata: #{({ success: true, cited_events: [] }).to_json}\n\n"
      end
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Chat streaming failed: #{e.message}")
      response.stream.write "event: error\ndata: #{({ message: e.message }).to_json}\n\n"
    rescue => e
      Rails.logger.error("Chat streaming error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      response.stream.write "event: error\ndata: #{({ message: "An unexpected error occurred" }).to_json}\n\n"
    ensure
      response.stream.close
    end
  end

  private

  def event_summary(event)
    {
      id: event.id,
      content: event.content.to_s.truncate(300),
      source_name: event.source&.name || "Unknown",
      published_at: event.published_at&.strftime("%b %d, %Y")
    }
  end
end
