# frozen_string_literal: true

class EventsController < ApplicationController
  # Hard ceiling on how many events one request may queue for rating. Each event
  # costs up to 3 paid AI calls, so "rate everything" on a large account is real
  # money and days of queue time.
  MAX_BULK_RATE_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

  def index
    @events = filtered_events
      .includes(:source, channel_events: :channel)
      .page(params[:page])
    # Source list for the filter dropdown. Sorted so the named sources come
    # first; the unnamed auto-created "manual" source is labelled in the view.
    @filter_sources = current_user.sources
      .order(Arel.sql("CASE WHEN name IS NULL OR name = '' THEN 1 ELSE 0 END"), :name)
  end

  def show
    @event = current_user.events.find(params[:id])
    @channel_events = @event.channel_events
      .includes(:channel)
      .order(relevance_score: :desc)
  end

  def bulk_rate
    requested_ids = extract_event_ids(params[:event_ids])
    explicit_selection = requested_ids.any?

    # An explicit selection rates exactly those events; otherwise rate what the
    # user is actually looking at — the same filtered scope the index shows.
    scope = explicit_selection ? current_user.events.where(id: requested_ids).recent : filtered_events

    matching_count = scope.count

    if matching_count.zero?
      redirect_to events_path(filter_params), alert: "No events match current filters"
      return
    end

    # `recent` orders newest first, so the cap keeps the most recent N.
    event_ids = scope.limit(MAX_BULK_RATE_EVENTS).pluck(:id)
    skipped = matching_count - event_ids.size
    channel_count = current_user.channels.count

    if channel_count.zero?
      redirect_to events_path(filter_params), alert: "No channels to rate against — create a channel first"
      return
    end

    current_user.channels.find_each do |channel|
      RateEventsJob.enqueue_batches(channel.id, event_ids)
    end

    notice = if explicit_selection
      "Rating queued for #{event_ids.size} selected events across #{channel_count} channel(s)"
    else
      "Rerating queued for #{event_ids.size} matching events across #{channel_count} channel(s)"
    end

    if skipped > 0
      notice += ". #{skipped} older event(s) were skipped — a single request rates at most #{MAX_BULK_RATE_EVENTS} events. Narrow the filters or repeat to cover the rest."
    end

    redirect_to events_path(filter_params), notice: notice
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

  private

  # Shared by #index and #bulk_rate so the count shown on the page is the set
  # that actually gets rated.
  def filtered_events
    scope = current_user.events.recent
    scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    if params[:search].present?
      # Escape LIKE metacharacters, otherwise a search for "%" matches every row
      # and forces a full scan. "!" as the escape char behaves the same on
      # SQLite (dev) and MariaDB (production); "\" does not.
      pattern = ActiveRecord::Base.sanitize_sql_like(params[:search].to_s, "!")
      scope = scope.where("content LIKE ? ESCAPE '!'", "%#{pattern}%")
    end
    scope
  end

  def filter_params
    params.permit(:source_id, :event_type, :search).to_h.compact_blank
  end

  # `event_ids` arrives as an array of checkbox values, but a hand-crafted or
  # buggy request can send a bare string (or a JSON-encoded array from the
  # bulk-select Stimulus controller). Never call Array methods on it blindly.
  def extract_event_ids(raw)
    values = case raw
    when Array
      raw
    when String
      stripped = raw.strip
      if stripped.start_with?("[")
        begin
          JSON.parse(stripped)
        rescue JSON::ParserError
          []
        end
      else
        stripped.split(",")
      end
    when ActionController::Parameters
      raw.to_unsafe_h.values
    else
      []
    end

    Array(values).flatten.map { |v| v.to_s.strip }.compact_blank.uniq
  end
end
