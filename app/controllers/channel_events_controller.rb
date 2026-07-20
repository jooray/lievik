# frozen_string_literal: true

class ChannelEventsController < ApplicationController
  before_action :set_channel

  def bulk_mark_used
    event_ids = parse_event_ids(params[:event_ids])

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
    event_ids = parse_event_ids(params[:event_ids])

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used]), alert: "No events selected"
      return
    end

    event_ids = current_user.events.where(id: event_ids).pluck(:id)

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used]), alert: "No events selected"
      return
    end

    RateEventsJob.perform_later(@channel.id, event_ids)

    notice = "Rerating queued for #{event_ids.size} event#{event_ids.size != 1 ? 's' : ''}"
    redirect_to channel_path(@channel, show_used: params[:show_used]), notice: notice
  end

  private

  # `event_ids` is either an array of checkbox values or a JSON-encoded array
  # from the bulk-select Stimulus controller. A hand-crafted request can send
  # anything at all, so never let JSON.parse (or its result) blow up the action.
  def parse_event_ids(raw)
    return [] if raw.blank?

    values = if raw.is_a?(String)
      begin
        JSON.parse(raw)
      rescue JSON::ParserError, TypeError
        []
      end
    else
      raw
    end

    Array.wrap(values).reject { |v| v.blank? || !v.to_s.match?(/\A\d+\z/) }
  end

  def set_channel
    channel_id = params[:channel_id] || params[:id]
    @channel = current_user.channels.find(channel_id)
  end
end
