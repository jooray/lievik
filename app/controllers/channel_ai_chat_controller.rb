# frozen_string_literal: true

class ChannelAiChatController < ApplicationController
  include ActionController::Live
  include SseStreaming

  requires_paid_ai kind: "chat", prompt: :message, only: :stream

  def index
    @existing_channels_count = current_user.channels.count
  end

  def stream
    stream_sse do |sse|
      Streams::ChannelProposal.new(current_user).call(sse, message: params[:message], history: params[:history])
    end
  end

  def bulk_create
    result = Channels::BulkCreator.new(current_user, channels: params[:channels], templates: params[:templates]).call

    if result.ok?
      render json: { success: true, count: result.count, redirect_to: channels_path }
    else
      render json: { success: false, error: result.error }, status: :unprocessable_entity
    end
  end
end
