# frozen_string_literal: true

class ChannelAiChatController < ApplicationController
  include ActionController::Live

  def index
    @existing_channels_count = current_user.channels.count
  end

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    message = params[:message].to_s.strip
    history_param = params[:history]
    conversation_history = history_param.is_a?(Array) ? history_param : JSON.parse(history_param || "[]")

    if message.blank?
      response.stream.write "event: error\ndata: #{({ message: "Please enter a message" }).to_json}\n\n"
      response.stream.close
      return
    end

    service = Ai::ChannelProposalService.new(current_user)

    begin
      service.chat_stream(message, conversation_history: conversation_history) do |event|
        case event[:type]
        when "chunk"
          response.stream.write "event: chunk\ndata: #{event[:data].to_json}\n\n"
        when "proposal"
          response.stream.write "event: proposal\ndata: #{event[:data].to_json}\n\n"
        when "complete"
          response.stream.write "event: complete\ndata: #{event[:data].to_json}\n\n"
        when "error"
          response.stream.write "event: error\ndata: #{event[:data].to_json}\n\n"
        end
      end
    rescue => e
      Rails.logger.error("Channel AI chat streaming error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      response.stream.write "event: error\ndata: #{({ message: "An unexpected error occurred" }).to_json}\n\n"
    ensure
      response.stream.close
    end
  end

  def bulk_create
    channels_data = params[:channels] || []
    templates_data = params[:templates] || []

    if channels_data.empty?
      render json: { success: false, error: "No channels to create" }, status: :unprocessable_entity
      return
    end

    created_channels = []

    ActiveRecord::Base.transaction do
      # Create templates first
      templates_data.each do |template|
        next if template[:name].blank? || template[:template].blank?
        # Skip if template with same name already exists
        existing = current_user.content_templates_list.find { |t| t["name"] == template[:name] }
        next if existing

        current_user.add_content_template(
          name: template[:name],
          template: template[:template]
        )
      end

      # Create channels
      channels_data.each do |channel_data|
        channel = current_user.channels.create!(
          name: channel_data[:name],
          description: channel_data[:description],
          language: channel_data[:language] || "en",
          prompt: channel_data[:prompt],
          content_style: channel_data[:content_style],
          content_language: channel_data[:content_language] || channel_data[:language],
          settings: {
            "relevance_threshold" => (channel_data.dig(:settings, :relevance_threshold) || 50).to_i,
            "humanize_output" => channel_data.dig(:settings, :humanize_output) != false
          }
        )
        created_channels << channel
      end
    end

    # Queue rating jobs for each new channel (outside transaction)
    created_channels.each do |channel|
      queue_initial_rating(channel)
    end

    render json: {
      success: true,
      count: created_channels.size,
      redirect_to: channels_path
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def queue_initial_rating(channel)
    recent_event_ids = current_user.sources
      .joins(:events)
      .where("events.published_at >= ?", 3.months.ago)
      .pluck("events.id")

    return if recent_event_ids.empty?

    RateEventsJob.perform_later(channel.id, recent_event_ids)
  end
end
