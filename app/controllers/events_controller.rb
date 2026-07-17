# frozen_string_literal: true

class EventsController < ApplicationController
  def index
    @events = current_user.events
      .includes(:source, channel_events: :channel)
      .recent

    @events = @events.where(source_id: params[:source_id]) if params[:source_id].present?
    @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
    @events = @events.where("content LIKE ?", "%#{params[:search]}%") if params[:search].present?

    @events = @events.page(params[:page])
  end

  def show
    @event = current_user.events.find(params[:id])
    @channel_events = @event.channel_events
      .includes(:channel)
      .order(relevance_score: :desc)
  end

  def bulk_rate
    event_ids_param = params[:event_ids]&.reject(&:blank?) || []

    if event_ids_param.empty?
      scope = current_user.events.recent
      scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
      scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
      event_ids = scope.pluck(:id)

      if event_ids.empty?
        redirect_to events_path(params.permit(:source_id, :event_type).to_h), alert: "No events match current filters"
        return
      end

      notice = "Rerating queued for all #{event_ids.size} matching events across all channels"
    else
      event_ids = event_ids_param
      notice = "Rating queued for #{event_ids.size} selected events across all channels"
    end

    current_user.channels.find_each do |channel|
      RateEventsJob.perform_later(channel.id, event_ids)
    end

    redirect_to events_path(params.permit(:source_id, :event_type).to_h), notice: notice
  end

  def bulk_mark_used
    @event = current_user.events.find(params[:id])

    # Parse JSON array from hidden field
    channel_event_ids = if params[:channel_event_ids].is_a?(String) && params[:channel_event_ids].start_with?("[")
      JSON.parse(params[:channel_event_ids]) rescue []
    else
      Array(params[:channel_event_ids]).reject(&:blank?)
    end

    if channel_event_ids.empty?
      redirect_to event_path(@event), alert: "No channels selected"
      return
    end

    # Only update channel_events that belong to this event and user's channels
    channel_events = ChannelEvent.joins(:channel)
      .where(id: channel_event_ids, event: @event)
      .where(channels: { user_id: current_user.id })

    updated_count = channel_events.update_all(used: true, used_at: Time.current)

    redirect_to event_path(@event), notice: "Marked as used in #{updated_count} channel(s)"
  end

end
