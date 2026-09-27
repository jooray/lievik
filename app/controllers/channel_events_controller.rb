# frozen_string_literal: true

class ChannelEventsController < ApplicationController
  before_action :set_channel

  def bulk_mark_used
    event_ids = parse_event_ids(params[:event_ids])

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), alert: t("channel_events.no_selection")
      return
    end

    channel_events = @channel.channel_events.where(event_id: event_ids)
    channel_events.update_all(used: true, used_at: Time.current)

    notice = t(".notice", count: channel_events.size)
    redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), notice: notice
  end

  def bulk_rate
    event_ids = parse_event_ids(params[:event_ids])

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), alert: t("channel_events.no_selection")
      return
    end

    event_ids = current_user.events.where(id: event_ids).pluck(:id)

    if event_ids.empty?
      redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), alert: t("channel_events.no_selection")
      return
    end

    RateEventsJob.perform_later(@channel.id, event_ids)

    notice = t(".notice", count: event_ids.size)
    redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), notice: notice
  end

  private

  # Bulk actions redirect back to the list the user was looking at, so the sort
  # has to survive the round trip. Whitelisted for the same reason it is in
  # ChannelsController: it ends up choosing an ORDER BY.
  def sort_param
    params[:sort] if ChannelsController::SORT_OPTIONS.include?(params[:sort]) &&
      params[:sort] != ChannelsController::DEFAULT_SORT
  end

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
