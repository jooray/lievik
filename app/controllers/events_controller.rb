# frozen_string_literal: true

class EventsController < ApplicationController
  requires_paid_access only: :bulk_rate

  # Hard ceiling on how many events one request may queue for rating. Each event
  # costs up to 3 paid AI calls, so "rate everything" on a large account is real
  # money and days of queue time.
  MAX_BULK_RATE_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

  def index
    @events = Events::Filter.call(current_user, filter_params)
      .includes(:source, channel_events: :channel)
      .page(params[:page])
    # Source list for the filter dropdown. Sorted so the named sources come
    # first; the unnamed auto-created "manual" source is labelled in the view.
    @filter_sources = Events::Filter.sources(current_user)
  end

  def show
    @event = current_user.events.find(params[:id])
    @channel_events = @event.channel_events
      .includes(:channel)
      .order(relevance_score: :desc)
  end

  # Same selection, cap and notice as the app API (Events::BulkRate).
  def bulk_rate
    result = Events::BulkRate.new(current_user, event_ids: params[:event_ids], filter: filter_params).call
    redirect_to events_path(filter_params), (result.ok? ? :notice : :alert) => result.message
  end

  def bulk_mark_used
    @event = current_user.events.find(params[:id])
    result = Events::MarkUsed.call(current_user, @event, params[:channel_event_ids])
    redirect_to event_path(@event), (result.ok? ? :notice : :alert) => result.message
  end

  private

  def filter_params
    params.permit(:source_id, :event_type, :search).to_h.compact_blank
  end
end
