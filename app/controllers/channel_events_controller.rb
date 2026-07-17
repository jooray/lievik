# frozen_string_literal: true

class ChannelEventsController < ApplicationController
  before_action :set_channel
  before_action :set_channel_event, only: [:show, :mark_used, :mark_unused]

  def index
    @threshold = params[:threshold]&.to_i || @channel.relevance_threshold
    @show_used = params[:show_used] == "true"

    @channel_events = @channel.channel_events
      .includes(event: [:source, :linked_contents])
      .above_threshold(@threshold)

    @channel_events = @channel_events.unused unless @show_used
    @channel_events = @channel_events.by_relevance.page(params[:page])
  end

  def show
    @event = @channel_event.event
  end

  def mark_used
    @channel_event.mark_used!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to channel_events_path(@channel) }
    end
  end

  def mark_unused
    @channel_event.mark_unused!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to channel_events_path(@channel) }
    end
  end

  def bulk_mark_used
    event_ids_json = params[:event_ids]
    event_ids = if event_ids_json.is_a?(String)
      JSON.parse(event_ids_json)
    else
      Array.wrap(event_ids_json).reject(&:blank?)
    end

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used]), alert: "No events selected"
      return
    end

    channel_events = @channel.channel_events.where(event_id: event_ids)
    channel_events.update_all(used: true, used_at: Time.current)

    notice = "Marked #{channel_events.size} events as used"
    redirect_to channel_path(@channel, show_used: params[:show_used]), notice: notice
  end

  def bulk_rate
    event_ids_json = params[:event_ids]

    event_ids = if event_ids_json.blank?
      []
    elsif event_ids_json.is_a?(String)
      begin
        JSON.parse(event_ids_json)
      rescue JSON::ParserError
        []
      end
    else
      Array.wrap(event_ids_json).reject(&:blank?)
    end

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used]), alert: "No events selected"
      return
    end

    RateEventsJob.perform_later(@channel.id, event_ids)

    notice = "Rerating queued for #{event_ids.size} event#{event_ids.size != 1 ? 's' : ''}"
    redirect_to channel_path(@channel, show_used: params[:show_used]), notice: notice
  end

  private

  def set_channel
    channel_id = params[:channel_id] || params[:id]
    @channel = current_user.channels.find(channel_id)
  end

  def set_channel_event
    @channel_event = @channel.channel_events.find(params[:id])
  end
end
